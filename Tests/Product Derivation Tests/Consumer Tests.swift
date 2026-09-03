import Product_Derivation
import Testing

@Product
private protocol Greeting {
    func greet(name: String) async throws -> String
}

private enum Counter {
    @Product
    protocol `Protocol` {
        func increment(limit: Int) async throws(Limit) -> Int
    }

    enum Limit: Swift.Error {
        case exceeded
    }
}

private enum Example {
    @Product
    protocol `Protocol` {
        var greeting: Greeting.Product { get }
        var counter: Counter.Product { get }
    }
}

private struct LinearInput: ~Copyable {
    let value: Int
}

private struct LinearOutput: ~Copyable {
    let value: Int
}

@Product
private protocol LinearTransform {
    associatedtype Input: ~Copyable
    associatedtype Output: ~Copyable

    func transform(
        _ input: borrowing Input,
        into output: consuming Output
    ) -> Int
}

@Product
private protocol Mutation {
    associatedtype Value

    func mutate(_ value: inout Value)
}

private func use<Client: Greeting>(_ client: Client) async throws -> String {
    try await client.greet(name: "Blob")
}

extension `Product Derivation Tests` {
    @Suite
    struct Consumer {
        @Test
        func `generated product carries an effectful operation`() async throws {
            let product = Greeting.Product(greet: { name in "Hello, \(name)!" })
            let greeting = try await use(product)

            #expect(greeting == "Hello, Blob!")
        }

        @Test
        func `generated product preserves noncopyable parameter ownership`() {
            let product = LinearTransform.Product<LinearInput, LinearOutput>(
                transform: { input, output in input.value + output.value }
            )
            let input = LinearInput(value: 20)

            #expect(
                product.transform(
                    input,
                    into: LinearOutput(value: 22)
                ) == 42
            )
            #expect(input.value == 20)
        }

        @Test
        func `generated product forwards inout coordinates`() {
            let product = Mutation.Product<Int>(mutate: { $0 += 1 })
            var value = 41

            product.mutate(&value)

            #expect(value == 42)
        }

        @Test
        func `nested semantic protocol derives its conforming product`() async throws {
            let counter = Counter.Product(increment: { $0 + 1 })
            let example = Example.Product(
                greeting: Greeting.Product(greet: { "Hello, \($0)!" }),
                counter: counter
            )

            let _: any Counter.`Protocol` = counter
            let _: any Example.`Protocol` = example
            #expect(try await example.counter.increment(limit: 2) == 3)
            #expect(try await example.greeting.greet(name: "Blob") == "Hello, Blob!")
        }
    }
}
