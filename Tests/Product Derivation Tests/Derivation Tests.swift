import SwiftParser
import SwiftSyntax
import Testing

@testable import Product_Derivation_Core

@Suite
struct `Product Derivation Tests` {
    @Test
    func `protocol operations derive one product structure`() throws {
        let source = Parser.parse(
            source: """
                protocol Greeting {
                    func greet(_ name: String) -> String
                    func reset()
                }
                """
        )
        let protocolDeclaration = try #require(
            source.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let analysis = Derivation.Analysis(protocolDeclaration)
        let declarations = Derivation.peers(of: analysis)
        let product = try #require(declarations.first?.as(StructDeclSyntax.self))

        #expect(declarations.count == 1)
        #expect(analysis.diagnostics.isEmpty)
        #expect(product.name.text == "__Greeting")
        #expect(product.memberBlock.members.count == 5)
    }

    @Test
    func `empty protocol derives an empty product`() throws {
        let source = Parser.parse(source: "protocol Empty {}")
        let protocolDeclaration = try #require(
            source.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let analysis = Derivation.Analysis(protocolDeclaration)
        let declarations = Derivation.peers(of: analysis)
        let product = try #require(declarations.first?.as(StructDeclSyntax.self))

        #expect(product.name.text == "__Empty")
        #expect(analysis.diagnostics.isEmpty)
        #expect(product.memberBlock.members.count == 1)
    }

    @Test
    func `analysis records ordered coordinates and parameter conventions once`() throws {
        let source = Parser.parse(
            source: """
                protocol Transform {
                    associatedtype Input: ~Copyable
                    func transform(
                        _ input: borrowing Input,
                        into output: consuming Output
                    ) -> Result
                    var result: Result { get }
                }
                """
        )
        let protocolDeclaration = try #require(
            source.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let analysis = Derivation.Analysis(protocolDeclaration)
        let function = try #require(analysis.functionCoordinates.first)

        #expect(analysis.diagnostics.isEmpty)
        #expect(analysis.coordinates.count == 3)
        #expect(analysis.associatedTypeCoordinates.map(\.name.text) == ["Input"])
        #expect(analysis.propertyCoordinates.map(\.name.text) == ["result"])
        #expect(function.name.text == "transform")
        #expect(function.parameters.map(\.localName.text) == ["input", "output"])
        #expect(function.parameters.map(\.closureType.trimmedDescription) == [
            "borrowing Input",
            "consuming Output",
        ])
        #expect(function.parameters.map(\.valueType.trimmedDescription) == [
            "Input",
            "Output",
        ])
        #expect(function.parameters.map(\.transfersOwnership) == [false, true])
        #expect(
            function.closureType.trimmedDescription
                == "(borrowing Input, consuming Output) -> Result"
        )
        #expect(function.output.trimmedDescription == "Result")
        #expect(
            function.invocation.trimmedDescription
                == "(self._transform)(input, output)"
        )
    }
}
