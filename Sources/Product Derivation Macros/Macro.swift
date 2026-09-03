import SwiftSyntax
import SwiftSyntaxMacros
import Product_Derivation_Core

public struct Macro: PeerMacro, ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let declaration = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Product applies to a protocol declaration only.")
        }
        let analysis = Product.Analysis(declaration)
        guard analysis.diagnostics.isEmpty else {
            throw MacroExpansionErrorMessage(
                "@Product cannot represent every requirement: \(analysis.diagnostics.joined(separator: "; "))."
            )
        }
        return Product.Derivation.peers(of: analysis)
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let declaration = declaration.as(ProtocolDeclSyntax.self) else { return [] }
        let analysis = Product.Analysis(declaration)
        guard analysis.diagnostics.isEmpty else { return [] }
        return Product.Derivation.extensions(of: analysis, type: type)
    }
}
