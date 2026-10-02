/// Runs `operation` for every input concurrently and concatenates the results.
///
/// Individual failures are tolerated so one inaccessible scope doesn't hide the rest;
/// an error is thrown only when every call fails.
func gatherConcurrently<Input, Output>(
    _ inputs: [Input],
    _ operation: @escaping (Input) async throws -> [Output]
) async throws -> [Output] {
    let (outputs, firstError, succeeded) = await withTaskGroup(of: Result<[Output], Error>.self) { group in
        for input in inputs {
            group.addTask {
                do {
                    return .success(try await operation(input))
                } catch {
                    return .failure(error)
                }
            }
        }

        var outputs: [Output] = []
        var firstError: Error?
        var succeeded = false

        for await result in group {
            switch result {
            case let .success(values):
                succeeded = true
                outputs.append(contentsOf: values)
            case let .failure(error):
                firstError = firstError ?? error
            }
        }

        return (outputs, firstError, succeeded)
    }

    if !succeeded, let firstError {
        throw firstError
    }
    return outputs
}
