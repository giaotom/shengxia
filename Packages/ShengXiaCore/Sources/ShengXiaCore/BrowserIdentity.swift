import Foundation

public enum BrowserIdentity {
    /// Desktop Chrome. Bilibili's public JSON APIs accept it, and Douyin's web player
    /// (the one that still requests aweme/detail) is the desktop site.
    public static let desktop =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    public static let iphone =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
}
