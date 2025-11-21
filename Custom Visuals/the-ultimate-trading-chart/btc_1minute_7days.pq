// ======================================================================
// BTC (GBP) — 1-MINUTE HISTORICAL MARKET DATA 
// GitHub: https://github.com/nathansmithbi/powerbi-resources
//

let
    // ===== SETTINGS ===================================================
    DaysBack = 7,      // <<< CHANGE THIS (5 or 7 days recommended)
    Symbol = "BTC",
    Tsym = "GBP",
    RowsPerCall = 2000,
    BaseUrl = "https://min-api.cryptocompare.com/data/v2/histominute",

    // ===== UNIX TIMESTAMP NOW =========================================
    UnixNow =
        Number.From(
            Duration.TotalSeconds(
                DateTimeZone.UtcNow()
                - #datetimezone(1970,1,1,0,0,0,0,0)
            )
        ),

    TargetTs = UnixNow - (DaysBack * 24 * 60 * 60),

    // ===== SAFE PAGE FETCHER ==========================================
    GetPage = (toTs as nullable number) as table =>
        let
            QueryParams =
                if toTs <> null then
                    [
                        fsym = Symbol,
                        tsym = Tsym,
                        limit = Text.From(RowsPerCall - 1),
                        toTs = Number.ToText(toTs)
                    ]
                else
                    [
                        fsym = Symbol,
                        tsym = Tsym,
                        limit = Text.From(RowsPerCall - 1)
                    ],

            Raw = Web.Contents(BaseUrl, [Query = QueryParams]),
            Json = try Json.Document(Raw) otherwise null,

            IsValid =
                Json <> null
                and Record.HasFields(Json, "Data")
                and Record.HasFields(Json[Data], "Data"),

            TableOut =
                if IsValid then
                    Table.FromRecords(Json[Data][Data])
                else
                    #table({"time","open","high","low","close","volumefrom","volumeto"}, {})
        in
            TableOut,

    // ===== PAGING LOOP (STOP WHEN OLDEST < TargetTs) ===================
    Pages =
        List.Generate(
            () =>
                let
                    First = GetPage(null),
                    Oldest =
                        if Table.RowCount(First) > 0 then
                            List.Min(First[time])
                        else
                            UnixNow
                in
                    [Page = First, Oldest = Oldest],

            each [Oldest] > TargetTs,

            each
                let
                    NextPage = GetPage([Oldest]),
                    NextOldest =
                        if Table.RowCount(NextPage) > 0 then
                            List.Min(NextPage[time])
                        else
                            [Oldest]
                in
                    [Page = NextPage, Oldest = NextOldest],

            each [Page]
        ),

    Combined = Table.Combine(Pages),

    // ===== FILTER TO EXACT WINDOW =====================================
    Filtered =
        Table.SelectRows(Combined, each [time] >= TargetTs),

    // ===== ADD DATETIME ===============================================
    AddDate =
        Table.AddColumn(
            Filtered,
            "Date",
            each #datetime(1970,1,1,0,0,0) + #duration(0,0,0,[time]),
            type datetime
        ),

    // ===== SINGLE “VOLUME” COLUMN (volumeto) ==========================
    AddVolume =
        Table.AddColumn(
            AddDate,
            "volume",
            each [volumeto],
            type number
        ),

    // ===== FINAL OUTPUT ===============================================
    Final =
        Table.SelectColumns(
            AddVolume,
            {"Date","open","high","low","close","volume"}
        )

in
    Final