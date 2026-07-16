import Foundation

public struct StoryBlueprint {

    let root: ContainerNode

    /// The no-JSON seam (DDD-2): wrap an already-built runtime tree directly,
    /// bypassing the JSON decode path. Consumed by the native compiler via the
    /// existing `Story(blueprint:)` surface.
    init(root: ContainerNode) {
        self.root = root
    }

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
            case .probeClassificationDrift:
                // Probe-only failure (DD-4); decode() never throws it, but the
                // switch must stay exhaustive. Surface as a probe failure.
                throw StoryError.decoderProbeFailure(reason: "number/bool classification drift")
            }
        } catch {
            throw StoryError.invalidJSON
        }

        root = container
    }
}
