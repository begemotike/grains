/// The binding weekly CSV schema (docs/csv-export.md). A column change bumps `version` and
/// the file name gains a `.v2` suffix so importers never silently break.
public enum CSVSchema {
    /// Schema version of the columns below.
    public static let version = 1

    /// Header row, in output order.
    public static let columns: [String] = [
        "id",
        "week",
        "started_at",
        "stopped_at",
        "started_local_date",
        "started_local_time",
        "stopped_local_date",
        "stopped_local_time",
        "duration_seconds",
        "whole_duration_seconds",
        "hours",
        "raw_text",
        "client_text",
        "note",
        "client_id",
        "running",
        "recovered",
        "created_at",
        "updated_at",
    ]
}
