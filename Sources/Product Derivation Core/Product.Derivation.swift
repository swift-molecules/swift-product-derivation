public import SwiftSyntax
import SwiftSyntaxBuilder

extension Product {
    public enum Derivation {
        public static func peers(of analysis: Analysis) -> [DeclSyntax] {
            let protocolDeclaration = analysis.declaration
            let access = analysis.access.map { "\($0.name.text) " } ?? ""
            let semantic = protocolDeclaration.name.trimmedDescription
            let name = declaredName(of: protocolDeclaration)
            let nested = name == "Protocol"
            let product = nested ? "Product" : "__\(name)"
            let functions = analysis.functionCoordinates
            let properties = analysis.propertyCoordinates
            let genericParameters = analysis.associatedTypeCoordinates.map { coordinate in
                coordinate.constraint.map { "\(coordinate.name.text): \($0.trimmedDescription)" }
                    ?? coordinate.name.text
            }
            let genericClause = genericParameters.isEmpty
                ? ""
                : "<\(genericParameters.joined(separator: ", "))>"

            let storedFunctions = functions.map { function in
                "    private let _\(function.name.trimmedDescription): \(function.closureType.trimmedDescription)"
            }
            let storedProperties = properties.map { property in
                "    \(access)let \(property.name.text): \(property.type.trimmedDescription)"
            }
            let parameters = functions.map { function in
                "\(function.name.trimmedDescription): @escaping \(function.closureType.trimmedDescription)"
            } + properties.map { property in
                "\(property.name.text): \(property.type.trimmedDescription)"
            }
            let assignments = functions.map { function in
                "        self._\(function.name.trimmedDescription) = \(function.name.trimmedDescription)"
            } + properties.map { property in
                "        self.\(property.name.text) = \(property.name.text)"
            }
            let forwarding = functions.map { function in
                let statement = function.returnsVoid
                    ? function.invocation.trimmedDescription
                    : "return \(function.invocation.trimmedDescription)"
                return """
                        \(access)func \(function.name.trimmedDescription)\(function.declaration.signature.trimmedDescription) {
                            \(statement)
                        }
                    """
            }

            let initializer = """
                    \(access)init(\(parameters.joined(separator: ", "))) {
                \(assignments.joined(separator: "\n"))
                }
                """
            let members = (storedFunctions + storedProperties + [initializer] + forwarding)
                .joined(separator: "\n\n")
            return [DeclSyntax(stringLiteral: """
                \(access)struct \(product)\(genericClause): \(semantic) {
                \(members)
                }
                """)]
        }

        public static func extensions(
            of analysis: Analysis,
            type: some TypeSyntaxProtocol
        ) -> [ExtensionDeclSyntax] {
            let protocolDeclaration = analysis.declaration
            let name = declaredName(of: protocolDeclaration)
            guard name != "Protocol" else { return [] }
            let access = analysis.access.map { "\($0.name.text) " } ?? ""
            let product = "__\(name)"
            let declaration: DeclSyntax = """
                extension \(type.trimmed) {
                    \(raw: access)typealias Product = \(raw: product)
                }
                """
            return declaration.as(ExtensionDeclSyntax.self).map { [$0] } ?? []
        }

        private static func declaredName(of declaration: ProtocolDeclSyntax) -> String {
            let spelling = declaration.name.text
            guard spelling.first == "`", spelling.last == "`" else { return spelling }
            return String(spelling.dropFirst().dropLast())
        }
    }
}
