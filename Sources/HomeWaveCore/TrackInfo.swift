public struct TrackInfo: Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var playing: Bool

    public init(id: String, title: String, artist: String, album: String, playing: Bool) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.playing = playing
    }
}
