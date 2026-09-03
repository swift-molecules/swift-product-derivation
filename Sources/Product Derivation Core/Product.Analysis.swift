public import SwiftSyntax

extension Product {
    public struct Analysis {
        public enum Coordinate {
            case function(Function)
            case associatedType(AssociatedType)
            case property(Property)
        }

        public enum ParameterConvention {
            case value
            case borrowing
            case consuming
            case sending
            case `inout`
            case unsupported
        }

        public struct Parameter {
            public let declaration: FunctionParameterSyntax
            public let localName: TokenSyntax
            /// The stored value type, without parameter-passing specifiers.
            public let valueType: TypeSyntax
            public let closureType: TypeSyntax
            public let convention: ParameterConvention
            public let forwardingExpression: ExprSyntax
            public let ownedExpression: ExprSyntax

            /// Whether the declaration transfers an owned value into the call.
            public var transfersOwnership: Bool {
                switch convention {
                case .consuming, .sending:
                    true
                default:
                    false
                }
            }

            public var isInout: Bool {
                if case .inout = convention { true } else { false }
            }
        }

        public struct Function {
            public let declaration: FunctionDeclSyntax
            public let name: TokenSyntax
            public let parameters: [Parameter]
            public let closureType: TypeSyntax
            public let output: TypeSyntax
            public let invocation: ExprSyntax
            public let returnsVoid: Bool
            public let thrownError: TypeSyntax?
            public let isUntypedThrows: Bool
            public let isRethrowing: Bool
        }

        public struct AssociatedType {
            public let declaration: AssociatedTypeDeclSyntax
            public let name: TokenSyntax
            public let constraint: TypeSyntax?
        }

        public struct Property {
            public let declaration: VariableDeclSyntax
            public let name: TokenSyntax
            public let type: TypeSyntax
        }

        public let declaration: ProtocolDeclSyntax
        public let access: DeclModifierSyntax?
        public let coordinates: [Coordinate]
        public let diagnostics: [String]

        public var functionCoordinates: [Function] {
            coordinates.compactMap { coordinate in
                guard case let .function(function) = coordinate else { return nil }
                return function
            }
        }

        public var associatedTypeCoordinates: [AssociatedType] {
            coordinates.compactMap { coordinate in
                guard case let .associatedType(associatedType) = coordinate else { return nil }
                return associatedType
            }
        }

        public var propertyCoordinates: [Property] {
            coordinates.compactMap { coordinate in
                guard case let .property(property) = coordinate else { return nil }
                return property
            }
        }

        public init(_ declaration: ProtocolDeclSyntax) {
            self.declaration = declaration
            access = Self.access(of: declaration)
            var coordinates: [Coordinate] = []
            var diagnostics: [String] = []
            var names: Set<String> = []

            for member in declaration.memberBlock.members {
                if let function = member.decl.as(FunctionDeclSyntax.self) {
                    let coordinate = Self.function(function)
                    Self.validate(
                        function,
                        parameters: coordinate.parameters,
                        isRethrowing: coordinate.isRethrowing,
                        names: &names,
                        reasons: &diagnostics
                    )
                    coordinates.append(.function(coordinate))
                } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                    if let property = Self.property(
                        variable,
                        names: &names,
                        reasons: &diagnostics
                    ) {
                        coordinates.append(.property(property))
                    }
                } else if let associated = member.decl.as(AssociatedTypeDeclSyntax.self) {
                    Self.validate(
                        associated,
                        names: &names,
                        reasons: &diagnostics
                    )
                    coordinates.append(
                        .associatedType(Self.associatedType(associated))
                    )
                } else {
                    diagnostics.append(
                        "`\(member.decl.trimmedDescription)` is not an operation or getter-only product coordinate"
                    )
                }
            }

            self.coordinates = coordinates
            self.diagnostics = diagnostics
        }

        private static func access(
            of declaration: ProtocolDeclSyntax
        ) -> DeclModifierSyntax? {
            for modifier in declaration.modifiers {
                switch modifier.name.tokenKind {
                case .keyword(.public), .keyword(.package), .keyword(.fileprivate):
                    return modifier
                case .keyword(.private):
                    return DeclModifierSyntax(name: .keyword(.fileprivate))
                default:
                    continue
                }
            }
            return nil
        }

        private static func validate(
            _ associated: AssociatedTypeDeclSyntax,
            names: inout Set<String>,
            reasons: inout [String]
        ) {
            let name = associated.name.text
            if !names.insert(name).inserted {
                reasons.append("`\(name)` duplicates another product coordinate")
            }
            if !associated.attributes.isEmpty || !associated.modifiers.isEmpty {
                reasons.append("`\(name)` has attributes or modifiers that are not plain product structure")
            }
            if associated.initializer != nil || associated.genericWhereClause != nil {
                reasons.append("`\(name)` has a default or where clause that the product family cannot preserve")
            }
            if (associated.inheritanceClause?.inheritedTypes.count ?? 0) > 1 {
                reasons.append("`\(name)` has multiple constraints that the product family cannot preserve")
            }
        }

        private static func validate(
            _ function: FunctionDeclSyntax,
            parameters: [Analysis.Parameter],
            isRethrowing: Bool,
            names: inout Set<String>,
            reasons: inout [String]
        ) {
            let name = function.name.trimmedDescription
            guard case .identifier = function.name.tokenKind else {
                reasons.append("`\(name)` is an operator requirement")
                return
            }
            if !names.insert(name).inserted {
                reasons.append("`\(name)` duplicates another product coordinate")
            }
            if !function.attributes.isEmpty {
                reasons.append("`\(name)` has attributes whose effects cannot be represented by the product field")
            }
            if !function.modifiers.isEmpty {
                reasons.append("`\(name)` has receiver or type modifiers whose effects cannot be represented by the product field")
            }
            if function.genericParameterClause != nil || function.genericWhereClause != nil {
                reasons.append("`\(name)` is generic; stored operation fields cannot be generic")
            }
            if isRethrowing {
                reasons.append("`\(name)` is rethrowing; stored function values cannot express rethrows")
            }
            if function.tokens(viewMode: .sourceAccurate).contains(where: {
                $0.tokenKind == .keyword(.Self)
            }) {
                reasons.append("`\(name)` refers to Self, which would change meaning on the generated product")
            }

            for parameter in parameters {
                let declaration = parameter.declaration
                let local = declaration.secondName ?? declaration.firstName
                if local.tokenKind == .wildcard {
                    reasons.append("`\(name)` has an unnamed parameter that cannot be forwarded")
                }
                if !declaration.attributes.isEmpty || !declaration.modifiers.isEmpty {
                    reasons.append("`\(name)` has a parameter convention whose effects cannot yet be represented")
                }
                if case .unsupported = parameter.convention {
                    reasons.append("`\(name)` has an unsupported parameter type specifier")
                }
                if declaration.ellipsis != nil {
                    reasons.append("`\(name)` has a variadic parameter; stored function values cannot be variadic")
                }
                if declaration.defaultValue != nil {
                    reasons.append("`\(name)` has a default argument that would be lost by the product field")
                }
            }
        }

        private static func property(
            _ variable: VariableDeclSyntax,
            names: inout Set<String>,
            reasons: inout [String]
        ) -> Analysis.Property? {
            guard
                variable.bindingSpecifier.tokenKind == .keyword(.var),
                variable.bindings.count == 1,
                let binding = variable.bindings.first,
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                let type = binding.typeAnnotation?.type,
                isGetterOnly(binding)
            else {
                reasons.append("`\(variable.trimmedDescription)` is not a getter-only property requirement")
                return nil
            }
            if !variable.attributes.isEmpty || !variable.modifiers.isEmpty {
                reasons.append("`\(name.text)` has attributes or modifiers that are not plain product structure")
            }
            if !names.insert(name.text).inserted {
                reasons.append("`\(name.text)` duplicates another product coordinate")
            }
            return Analysis.Property(declaration: variable, name: name, type: type)
        }

        private static func associatedType(
            _ declaration: AssociatedTypeDeclSyntax
        ) -> Analysis.AssociatedType {
            Analysis.AssociatedType(
                declaration: declaration,
                name: declaration.name,
                constraint: declaration.inheritanceClause?.inheritedTypes.first?.type
            )
        }

        private static func function(_ declaration: FunctionDeclSyntax) -> Analysis.Function {
            let parameters = declaration.signature.parameterClause.parameters.map { parameter in
                let value = parameterValue(of: parameter)
                let localName = parameter.secondName ?? parameter.firstName
                let reference = DeclReferenceExprSyntax(baseName: localName)
                return Analysis.Parameter(
                    declaration: parameter,
                    localName: localName,
                    valueType: value.type,
                    closureType: parameter.type,
                    convention: value.convention,
                    forwardingExpression: value.convention.isInout
                        ? ExprSyntax(InOutExprSyntax(expression: reference))
                        : ExprSyntax(reference),
                    ownedExpression: value.convention.isBorrowing
                        ? ExprSyntax(
                            CopyExprSyntax(
                                copyKeyword: .keyword(
                                    .copy,
                                    trailingTrivia: .space
                                ),
                                expression: reference
                            )
                        )
                        : ExprSyntax(reference)
                )
            }
            let output = declaration.signature.returnClause?.type
                ?? TypeSyntax(IdentifierTypeSyntax(name: .identifier("Void")))
            let effectSpecifiers = declaration.signature.effectSpecifiers
            let throwsClause = effectSpecifiers?.throwsClause
            let closureParameters = parameters.enumerated().map { offset, parameter in
                TupleTypeElementSyntax(
                    type: parameter.closureType,
                    trailingComma: offset == parameters.count - 1
                        ? nil
                        : .commaToken(trailingTrivia: .space)
                )
            }
            let typeEffects = effectSpecifiers.flatMap { effects in
                effects.asyncSpecifier == nil && effects.throwsClause == nil
                    ? nil
                    : TypeEffectSpecifiersSyntax(
                        asyncSpecifier: effects.asyncSpecifier,
                        throwsClause: effects.throwsClause
                    )
            }
            let closure = TypeSyntax(
                FunctionTypeSyntax(
                    parameters: TupleTypeElementListSyntax(closureParameters),
                    rightParen: .rightParenToken(trailingTrivia: .space),
                    effectSpecifiers: typeEffects,
                    returnClause: ReturnClauseSyntax(
                        arrow: .arrowToken(trailingTrivia: .space),
                        type: output
                    )
                )
            )
            let member = MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                declName: DeclReferenceExprSyntax(
                    baseName: .identifier("_\(declaration.name.text)")
                )
            )
            let callee = TupleExprSyntax(
                elements: LabeledExprListSyntax([
                    LabeledExprSyntax(expression: member)
                ])
            )
            let arguments = parameters.enumerated().map { offset, parameter in
                LabeledExprSyntax(
                    expression: parameter.forwardingExpression,
                    trailingComma: offset == parameters.count - 1
                        ? nil
                        : .commaToken(trailingTrivia: .space)
                )
            }
            var invocation = ExprSyntax(
                FunctionCallExprSyntax(
                    calledExpression: callee,
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax(arguments),
                    rightParen: .rightParenToken()
                )
            )
            if effectSpecifiers?.asyncSpecifier != nil {
                invocation = ExprSyntax(
                    AwaitExprSyntax(
                        awaitKeyword: .keyword(.await, trailingTrivia: .space),
                        expression: invocation
                    )
                )
            }
            if throwsClause != nil {
                invocation = ExprSyntax(
                    TryExprSyntax(
                        tryKeyword: .keyword(.try, trailingTrivia: .space),
                        expression: invocation
                    )
                )
            }
            let outputSpelling = output.trimmedDescription

            return Analysis.Function(
                declaration: declaration,
                name: declaration.name,
                parameters: parameters,
                closureType: closure,
                output: output,
                invocation: invocation,
                returnsVoid: outputSpelling == "Void" || outputSpelling == "()",
                thrownError: throwsClause?.type,
                isUntypedThrows: throwsClause != nil && throwsClause?.type == nil,
                isRethrowing: throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows)
            )
        }

        private static func parameterValue(
            of parameter: FunctionParameterSyntax
        ) -> (type: TypeSyntax, convention: Analysis.ParameterConvention) {
            guard var attributed = parameter.type.as(AttributedTypeSyntax.self) else {
                return (parameter.type, .value)
            }
            var convention = Analysis.ParameterConvention.value
            for specifier in attributed.specifiers {
                guard let simple = specifier.as(SimpleTypeSpecifierSyntax.self) else {
                    convention = .unsupported
                    break
                }
                switch simple.specifier.tokenKind {
                case .keyword(.borrowing), .identifier("__shared"):
                    convention = .borrowing
                case .keyword(.consuming), .identifier("__owned"):
                    convention = .consuming
                case .keyword(.sending):
                    convention = .sending
                case .keyword(.inout):
                    convention = .inout
                default:
                    convention = .unsupported
                }
            }
            attributed.specifiers = []
            return (TypeSyntax(attributed), convention)
        }

        private static func isGetterOnly(_ binding: PatternBindingSyntax) -> Bool {
            guard let accessors = binding.accessorBlock?.accessors else { return false }
            switch accessors {
            case let .accessors(list):
                guard list.count == 1, let accessor = list.first else { return false }
                return accessor.accessorSpecifier.tokenKind == .keyword(.get)
                    && accessor.body == nil
            case .getter:
                return false
            }
        }
    }
}

private extension Product.Analysis.ParameterConvention {
    var isBorrowing: Bool {
        if case .borrowing = self { true } else { false }
    }

    var isInout: Bool {
        if case .inout = self { true } else { false }
    }
}
