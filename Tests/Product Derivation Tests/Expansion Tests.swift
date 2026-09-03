import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import Product_Derivation_Macros

private let productMacros: [String: MacroSpec] = [
    "Product": MacroSpec(type: Product_Derivation_Macros.Macro.self)
]

private func expectProductExpansion(
    _ originalSource: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    assertMacroExpansion(
        originalSource,
        expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: productMacros,
        failureHandler: { failure in
            Issue.record(
                Comment(rawValue: failure.message),
                sourceLocation: SourceLocation(
                    fileID: failure.location.fileID.description,
                    filePath: failure.location.filePath.description,
                    line: Int(failure.location.line),
                    column: Int(failure.location.column)
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}

extension `Product Derivation Tests` {
    @Suite
    struct Expansion {
        @Test
        func `protocol expands to its operation product`() {
            expectProductExpansion(
                """
                @Product
                protocol Greeting {
                    func greet(name: String) -> String
                }
                """,
                expandedSource: """
                protocol Greeting {
                    func greet(name: String) -> String
                }

                struct __Greeting: Greeting {
                    private let _greet: (String) -> String

                    init(greet: @escaping (String) -> String) {
                        self._greet = greet
                    }

                    func greet(name: String) -> String {
                        return (self._greet)(name)
                    }
                }

                extension Greeting {
                    typealias Product = __Greeting
                }
                """
            )
        }

        @Test
        func `parameter ownership is preserved by the operation field`() {
            expectProductExpansion(
                """
                @Product
                protocol Transform {
                    associatedtype Input: ~Copyable
                    associatedtype Output: ~Copyable
                    func transform(_ input: borrowing Input, into output: consuming Output)
                }
                """,
                expandedSource: """
                protocol Transform {
                    associatedtype Input: ~Copyable
                    associatedtype Output: ~Copyable
                    func transform(_ input: borrowing Input, into output: consuming Output)
                }

                struct __Transform<Input: ~Copyable, Output: ~Copyable>: Transform {
                    private let _transform: (borrowing Input, consuming Output) -> Void

                    init(transform: @escaping (borrowing Input, consuming Output) -> Void) {
                        self._transform = transform
                    }

                    func transform(_ input: borrowing Input, into output: consuming Output) {
                        (self._transform)(input, output)
                    }
                }

                extension Transform {
                    typealias Product = __Transform
                }
                """
            )
        }

        @Test
        func `inout parameters are forwarded with an inout argument`() {
            expectProductExpansion(
                """
                @Product
                protocol Mutation {
                    associatedtype Value
                    func mutate(_ value: inout Value)
                }
                """,
                expandedSource: """
                protocol Mutation {
                    associatedtype Value
                    func mutate(_ value: inout Value)
                }

                struct __Mutation<Value>: Mutation {
                    private let _mutate: (inout Value) -> Void

                    init(mutate: @escaping (inout Value) -> Void) {
                        self._mutate = mutate
                    }

                    func mutate(_ value: inout Value) {
                        (self._mutate)(&value)
                    }
                }

                extension Mutation {
                    typealias Product = __Mutation
                }
                """
            )
        }

        @Test
        func `unsupported requirements are diagnosed instead of discarded`() {
            expectProductExpansion(
                """
                @Product
                protocol Greeting {
                    var salutation: String { get }
                    func greet<Value>(name: Value) -> String
                }
                """,
                expandedSource: """
                protocol Greeting {
                    var salutation: String { get }
                    func greet<Value>(name: Value) -> String
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@Product cannot represent every requirement: `greet` is generic; stored operation fields cannot be generic.",
                        line: 1,
                        column: 1
                    )
                ]
            )
        }

        @Test
        func `mutable property requirements are rejected`() {
            expectProductExpansion(
                """
                @Product
                protocol Counter {
                    var value: Int { get set }
                }
                """,
                expandedSource: """
                protocol Counter {
                    var value: Int { get set }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@Product cannot represent every requirement: `var value: Int { get set }` is not a getter-only property requirement.",
                        line: 1,
                        column: 1
                    )
                ]
            )
        }

        @Test
        func `non protocol attachment is diagnosed`() {
            expectProductExpansion(
                """
                @Product
                struct Greeting {}
                """,
                expandedSource: """
                struct Greeting {}
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@Product applies to a protocol declaration only.",
                        line: 1,
                        column: 1
                    )
                ]
            )
        }
    }
}
