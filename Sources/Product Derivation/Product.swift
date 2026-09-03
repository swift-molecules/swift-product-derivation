@attached(peer, names: named(Product), prefixed(__))
@attached(extension, names: named(Product))
public macro Product() = #externalMacro(
    module: "Product_Derivation_Macros",
    type: "Macro"
)
