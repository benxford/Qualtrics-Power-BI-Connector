// This file contains your Data Connector logic
[Version = "1.0.0"]
section Qualtrics;

/// ValidateUrlScheme - Validates that the URL scheme is HTTPS.
/// Required.
ValidateUrlScheme = (url as text) as text => if (Uri.Parts(url)[Scheme] <> "https") then error "Url scheme must be HTTPS" else url;

/// WaitFor - waits for producer to return a non-null value.
/// The amount of time between each call to producer is determined by the duration returned by interval.
/// producer - a function that returns a non-null value when available.
/// interval - a function that returns a duration specifying how long to wait before calling producer again.
/// count - the maximum number of times that producer will be called.
WaitFor = (producer as function, interval as function, optional count as number) as any =>
    let
        list = List.Generate(
            () => {0, null},
            (state) => state{0} <> null and (count = null or state{0} < count),
            (state) => if state{1} <> null then {null, state{1}} else {1 + state{0}, Function.InvokeAfter(() => producer(state{0}), interval(state{0}))},
            (state) => state{1})
    in
        List.Last(list);

/// ExportResponses - Starts an export of a survey's responses.
/// This is the first step in exporting the responses.
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
/// options - See https://api.qualtrics.com/6b00592b9c013-start-response-export.
ExportResponses = (dataCenter as text, surveyId as text, optional options as nullable record) => 
    let
        _defaultOptions = [format = "json", compress = false],
        _options = if options <> null then Record.Combine({options, _defaultOptions}) else _defaultOptions,
        _apiKey = if Record.HasFields(Extension.CurrentCredential(), "Key") then Extension.CurrentCredential()[Key] else null,
        _url = ValidateUrlScheme("https://" & dataCenter & ".qualtrics.com/API/v3/surveys/" & surveyId & "/export-responses"),
        _source = Json.Document(Web.Contents(_url, [ Headers = [ #"Content-Type" = "application/json", #"X-API-Token" = _apiKey ], ManualCredentials = true, Content = Json.FromValue(_options)]))
    in
        _source;


/// GetExportProgress - Retrieves the status of a response export for the given exportProgressId.
/// Continues polling every 10 seconds for up to 3 minutes, or until the export status is complete.
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
/// progressId - This is obtained by calling ExportResponses.
GetExportProgress = (dataCenter as text, surveyId as text, progressId as text) => 
    let
        _apiKey = if Record.HasFields(Extension.CurrentCredential(), "Key") then Extension.CurrentCredential()[Key] else null,
        _url = "https://" & dataCenter & ".qualtrics.com/API/v3/surveys/" & surveyId & "/export-responses/" & progressId,
        _source = WaitFor(
            (attempt) =>
                let
                    __isRetry = attempt > 0,
                    __source = Json.Document(Web.Contents(_url, [ Headers = [ #"Content-Type" = "application/json", #"X-API-Token" = _apiKey ], ManualCredentials = true, IsRetry = __isRetry ]))
                in
                    if __source[result][status] <> "complete" and __source[result][status] <> "failed" then null else __source,
            (attempt) => 
                #duration(0,0,0,10),
            18
        )
        
    in
        _source;

/// GetExportFile - Retrieves the response export file after the file export process completes.
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
/// QFileId - This is obtained by calling GetExportProgress.
GetExportFile = (dataCenter as text, surveyId as text, QFileID as text) => 
    let
        _apiKey = if Record.HasFields(Extension.CurrentCredential(), "Key") then Extension.CurrentCredential()[Key] else null,
        _url = ValidateUrlScheme("https://" & dataCenter & ".qualtrics.com/API/v3/surveys/" & surveyId & "/export-responses/" & QFileID & "/file"),
        _source = Json.Document(Web.Contents(_url, [ Headers = [ #"Content-Type" = "application/json", #"X-API-Token" = _apiKey ], ManualCredentials = true ]))
    in
        _source;


/// Gets a list of column renames based on the questions in the survey.
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
[DataSource.Kind="Qualtrics", AuthenticationKind = "Key"]
GetColumnRenames = (dataCenter as text, surveyId as text) => 
    let 
        _questions = GetSurveyQuestions(dataCenter, surveyId)[result][elements],
        _renames = List.Combine(List.Transform(_questions, each if _[QuestionType] = "TE" then {{[QuestionID] & "_TEXT", [QuestionText]}} else if [QuestionType] = "Matrix" then List.Transform(Record.FieldNames([Choices]), (fieldName) => {[QuestionID] & "_" & fieldName, Record.Field([Choices], fieldName)[Display]}) else {{[QuestionID], [QuestionText]}}))
    in
        List.Buffer(_renames);

/// GetSurveyQuestions - Calls the questions endpoint.
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
GetSurveyQuestions = (dataCenter as text, surveyId as text) => 
    let
        _apiKey = if Record.HasFields(Extension.CurrentCredential(), "Key") then Extension.CurrentCredential()[Key] else null,
        _url = ValidateUrlScheme("https://" & dataCenter & ".qualtrics.com/API/v3/survey-definitions/" & surveyId & "/questions"),
        _source = Json.Document(Web.Contents(_url, [ Headers = [ #"Content-Type" = "application/json", #"X-API-Token" = _apiKey ], ManualCredentials = true  ]))
    in
        _source;


/// Qualtrics.GetSurveyResponses - 
/// dataCenter - The Datacenter ID indicates your host data center, and can be found under your Qualtrics IDs tab in Qualtrics. You must make all public API requests to your host data center or the request will fail.
/// surveyId - The survey ID can be found under your Qualtrics IDs tab in Qualtrics.
/// renameColumns - If true, will attempt to rename the columns based on the survey questions. Otherwise, question IDs are used as column names.
/// options - See https://api.qualtrics.com/6b00592b9c013-start-response-export. Note: Not all options are supported.
[DataSource.Kind="Qualtrics", Publish="Qualtrics.Publish", AuthenticationKind = "Key"]
shared Qualtrics.GetSurveyResponses = (dataCenter as text, surveyId as text, optional renameColumns as nullable logical, optional options as nullable record) => 
    let
        _startExport = ExportResponses(dataCenter, surveyId, options),
        _exportProgress = GetExportProgress(dataCenter, surveyId, _startExport[result][progressId]),
        _exportFile = GetExportFile(dataCenter, surveyId, _exportProgress[result][fileId]),
        _transformRecords = List.Transform(_exportFile[responses], each Record.Combine({[responseId = [responseId]], [values]})),
        _recordFieldNames = List.Distinct(List.Combine(List.Transform(List.Range(_transformRecords, 0, 10), each Record.FieldNames(_)))),
        _convertToTable = Table.FromList(_transformRecords, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        _expandTable = Table.ExpandRecordColumn(_convertToTable, "Column1", _recordFieldNames, _recordFieldNames),
        _columnRenames = GetColumnRenames(dataCenter, surveyId),
        _maybeRenameColumns = if renameColumns = true then Table.RenameColumns(_expandTable, List.Select(GetColumnRenames(dataCenter, surveyId), each List.Contains(Table.ColumnNames(_expandTable), _{0}))) else _expandTable
    in
        _maybeRenameColumns;


// Data Source Kind description
Qualtrics = [
    TestConnection = (path as any) => { "Qualtrics.GetSurveyResponses", Json.Document(path)[dataCenter], Json.Document(path)[surveyId] },
    Authentication = [
        Key = [
        ]
    ]
];

// Data Source UI publishing description
Qualtrics.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://api.qualtrics.com/6b00592b9c013-start-response-export",
    SourceImage = Qualtrics.Icons,
    SourceTypeImage = Qualtrics.Icons
];

Qualtrics.Icons = [
    Icon16 = { Extension.Contents("Qualtrics16.png"), Extension.Contents("Qualtrics20.png"), Extension.Contents("Qualtrics24.png"), Extension.Contents("Qualtrics32.png") },
    Icon32 = { Extension.Contents("Qualtrics32.png"), Extension.Contents("Qualtrics40.png"), Extension.Contents("Qualtrics48.png"), Extension.Contents("Qualtrics64.png") }
];
