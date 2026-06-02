import Foundation

public struct StoryBlueprint {

    let root: ContainerNode

    public init(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw StoryError.invalidJSON
        }

        let decoder = InkDecoder()

        do {
            try decoder.probe()
        } catch {
            throw StoryError.decoderProbeFailure(reason: error.localizedDescription)
        }

        let container: ContainerNode
        do {
            container = try decoder.decode(data)
        } catch let error as InkDecodeError {
            switch error {
            case .unsupportedInkVersion(let version):
                throw StoryError.unsupportedInkVersion(version)
            case .malformedJSON:
                throw StoryError.invalidJSON
            }
        } catch {
            throw StoryError.invalidJSON
        }

        root = container
    }
}
