import OSLog

public enum EHLog {
    public static let network = Logger(subsystem: "com.liao.ehviewer", category: "network")
    public static let downloads = Logger(subsystem: "com.liao.ehviewer", category: "downloads")
    public static let persistence = Logger(subsystem: "com.liao.ehviewer", category: "persistence")
}
