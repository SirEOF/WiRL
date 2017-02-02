{******************************************************************************}
{                                                                              }
{       WiRL: RESTful Library for Delphi                                       }
{                                                                              }
{       Copyright (c) 2015-2017 WiRL Team                                      }
{                                                                              }
{       https://github.com/delphi-blocks/WiRL                                  }
{                                                                              }
{******************************************************************************}
unit WiRL.Tests.Mock.Server;

interface

uses
  System.Classes, System.SysUtils, System.RegularExpressions,
  System.Json, System.NetEncoding,

  WiRL.http.Core,
  WiRL.http.Accept.MediaType,
  WiRL.Core.Engine,
  WiRL.Core.Response,
  WiRL.Core.Request,
  WiRL.Core.Context;

type
  TWiRLResponseError = class(TObject)
  private
    FMessage: string;
    FStatus: string;
    FException: string;
  public
    property Message: string read FMessage write FMessage;
    property Status: string read FStatus write FStatus;
    property Exception: string read FException write FException;
  end;

  TWiRLTestServer = class(TObject)
  private
    FEngine: TWiRLEngine;
    FActive: Boolean;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure DoCommand(ARequest: TWiRLRequest; AResponse: TWiRLResponse);
    function ConfigureEngine(const ABasePath: string): TWiRLEngine;
    property Engine: TWiRLEngine read FEngine;
    property Active: Boolean read FActive write FActive;
  end;

  TWiRLTestResponse = class(TWiRLResponse)
  private
    FContentStream: TStream;
    FStatusCode: Integer;
    FContent: string;
    FReasonString: string;
    FResponseError: TWiRLResponseError;
  protected
    function GetContent: string; override;
    function GetContentStream: TStream; override;
    procedure SetContent(const Value: string); override;
    procedure SetContentStream(const Value: TStream); override;
    function GetStatusCode: Integer; override;
    procedure SetStatusCode(const Value: Integer); override;
    function GetReasonString: string; override;
    procedure SetReasonString(const Value: string); override;
  public
    procedure SendHeaders; override;
    property Error: TWiRLResponseError read FResponseError;
    constructor Create;
    destructor Destroy; override;
  end;

  TWiRLTestRequest = class(TWiRLRequest)
  private
    FCookieFields: TWiRLCookie;
    FQueryFields: TWiRLParam;
    FContentFields: TWiRLParam;
    FUrl: string;
    FProtocol: string;
    FHost: string;
    FPathInfo: string;
    FRawPathInfo: string;
    FQuery: string;
    FServerPort: Integer;
    FContentStream: TStream;
    FHeaderFields: TWiRLHeaderList;
    procedure ParseQueryParams;
    procedure SetUrl(const Value: string);
    function GetContent: string;
    procedure SetContent(const Value: string);
  protected
    function GetPathInfo: string; override;
    function GetQuery: string; override;
    function GetServerPort: Integer; override;
    function GetQueryFields: TWiRLParam; override;
    function GetContentFields: TWiRLParam; override;
    function GetCookieFields: TWiRLCookie; override;
    function GetContentStream: TStream; override;
    procedure SetContentStream(const Value: TStream); override;
    function GetRawPathInfo: string; override;
    function GetHeaderFields: TWiRLHeaderList; override;
  public
    property Url: string read FUrl write SetUrl;
    property Content: string read GetContent write SetContent;
    constructor Create;
    destructor Destroy; override;
  end;


implementation

{ TWiRLTestServer }

function TWiRLTestServer.ConfigureEngine(const ABasePath: string): TWiRLEngine;
begin
  FEngine.SetBasePath(ABasePath);
  Result := FEngine;
end;

constructor TWiRLTestServer.Create;
begin
  FEngine := TWiRLEngine.Create;
end;

destructor TWiRLTestServer.Destroy;
begin
  FEngine.Free;
  inherited;
end;

procedure TWiRLTestServer.DoCommand(ARequest: TWiRLRequest;
  AResponse: TWiRLResponse);
var
  LContext: TWiRLContext;
  LContentJson: TJSONValue;
begin
  inherited;

  LContext := TWiRLContext.Create;
  try
    LContext.Engine := FEngine;
    LContext.Request := ARequest;
    LContext.Response := AResponse;

    ARequest.ContentStream.Position := 0;

    FEngine.HandleRequest(LContext);
//    AResponseInfo.CustomHeaders.AddStrings(LContext.Response.CustomHeaders);
    if AResponse.StatusCode <> 200 then
    begin
      if AResponse.ContentType = TMediaType.APPLICATION_JSON then
      begin
        LContentJson := TJSONObject.ParseJSONValue(AResponse.Content);
        (AResponse as TWiRLTestResponse).Error.Message := LContentJson.GetValue<string>('message');
        (AResponse as TWiRLTestResponse).Error.Status := LContentJson.GetValue<string>('status');
        (AResponse as TWiRLTestResponse).Error.Exception := LContentJson.GetValue<string>('exception');
        //raise TWiRLTestException.Create(LMessage, LStatus, LException);
      end
      else
        raise Exception.Create(IntToStr(AResponse.StatusCode) + ' - ' + AResponse.ReasonString);
    end;

  finally
    LContext.Free;
  end;
end;

{ TWiRLTestRequest }

constructor TWiRLTestRequest.Create;
begin
  inherited;
  FContentStream := TMemoryStream.Create;
  FCookieFields := TWiRLCookie.Create;
  FQueryFields := TWiRLParam.Create;
  FContentFields := TWiRLParam.Create;
  FMethod := 'GET';
  FServerPort := 80;
end;

destructor TWiRLTestRequest.Destroy;
begin
  FCookieFields.Free;
  FQueryFields.Free;
  FContentFields.Free;
  inherited;
end;

function TWiRLTestRequest.GetContent: string;
begin
  Result := inherited Content;
end;

function TWiRLTestRequest.GetContentFields: TWiRLParam;
begin
  Result := FContentFields;
end;

function TWiRLTestRequest.GetContentStream: TStream;
begin
  Result := FContentStream;
end;

function TWiRLTestRequest.GetCookieFields: TWiRLCookie;
begin
  Result := FCookieFields;
end;

function TWiRLTestRequest.GetHeaderFields: TWiRLHeaderList;
begin
  if not Assigned(FHeaderFields) then
  begin
    FHeaderFields := TWiRLHeaderList.Create;
  end;
  Result := FHeaderFields;
end;

function TWiRLTestRequest.GetPathInfo: string;
begin
  Result := FPathInfo;
end;

function TWiRLTestRequest.GetQuery: string;
begin
  Result := FQuery;
end;

function TWiRLTestRequest.GetQueryFields: TWiRLParam;
begin
  Result := FQueryFields;
end;

function TWiRLTestRequest.GetRawPathInfo: string;
begin
  Result := FRawPathInfo;
end;

function TWiRLTestRequest.GetServerPort: Integer;
begin
  Result := FServerPort;
end;

procedure TWiRLTestRequest.ParseQueryParams;
var
  Params: TArray<string>;
  Param: string;
  EqualIndex: Integer;
begin
  FQueryFields.Clear;
  if FQuery <> '' then
  begin
    Params := FQuery.Split(['&']);
    for Param in Params do
    begin
      // I can't use split: I need only the first equal symbol
      EqualIndex := Param.IndexOf('=');
      if EqualIndex > 0 then
      begin
        FQueryFields.AddPair(TNetEncoding.URL.Decode(Param.Substring(0, EqualIndex)), TNetEncoding.URL.Decode(Param.Substring(EqualIndex + 1)));
      end;
    end;
  end;

end;

procedure TWiRLTestRequest.SetContent(const Value: string);
var
  Buffer: TBytes;
begin
  Buffer := EncodingFromCharSet(ContentMediaType.Charset).GetBytes(Value);
  FContentStream.Write(Buffer[0], Length(Buffer));
  FContentStream.Position := 0;
end;

procedure TWiRLTestRequest.SetContentStream(const Value: TStream);
begin
  inherited;
  if Assigned(FContentStream) then
    FContentStream.Free;
  FContentStream := Value;
end;

procedure TWiRLTestRequest.SetUrl(const Value: string);
const
  Pattern = '(https{0,1}):\/\/([^\/]+)(\/[^?\n]*)\?*(.*)';
var
  LRegEx: TRegEx;
  LMatch: TMatch;
  LPortIndex: Integer;
begin
  FUrl := Value;
  LRegEx := TRegEx.Create(Pattern, [roIgnoreCase, roMultiLine]);
  LMatch := LRegEx.Match(FUrl);
  if LMatch.Groups.Count > 1 then
    FProtocol := LMatch.Groups[1].Value;
  if LMatch.Groups.Count > 2 then
    FHost := LMatch.Groups[2].Value;
  if LMatch.Groups.Count > 3 then
  begin
    FPathInfo := LMatch.Groups[3].Value;
    FRawPathInfo := LMatch.Groups[3].Value;
  end;
  if LMatch.Groups.Count > 4 then
    FQuery := LMatch.Groups[4].Value;

  LPortIndex := FHost.IndexOf(':');
  if LPortIndex >= 0 then
    FServerPort := FHost.Substring(LPortIndex + 1).ToInteger
  else
    FServerPort := 80;

  ParseQueryParams;
end;

{ TWiRLTestResponse }

constructor TWiRLTestResponse.Create;
begin
  inherited;
  FResponseError := TWiRLResponseError.Create;
  FStatusCode := 200;
  FReasonString := 'OK';
end;

destructor TWiRLTestResponse.Destroy;
begin
  inherited;
end;

function TWiRLTestResponse.GetContent: string;
var
  LBuffer: TBytes;
begin
  if Assigned(FContentStream) and (FContentStream.Size > 0)  then
  begin
    FContentStream.Position := 0;
    SetLength(LBuffer, FContentStream.Size);
    FContentStream.Read(LBuffer[0], FContentStream.Size);
    // Should read the content-type
    Result := TEncoding.UTF8.GetString(LBuffer);
  end
  else
    Result := FContent;
end;

function TWiRLTestResponse.GetContentStream: TStream;
begin
  Result := FContentStream;
end;

function TWiRLTestResponse.GetReasonString: string;
begin
  Result := FReasonString;
end;

function TWiRLTestResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

procedure TWiRLTestResponse.SendHeaders;
begin
  inherited;
end;

procedure TWiRLTestResponse.SetContent(const Value: string);
begin
  inherited;
  FContent := Value;
end;

procedure TWiRLTestResponse.SetContentStream(const Value: TStream);
begin
  inherited;
  FContentStream := Value;
end;

procedure TWiRLTestResponse.SetReasonString(const Value: string);
begin
  inherited;
  FReasonString := Value;
end;

procedure TWiRLTestResponse.SetStatusCode(const Value: Integer);
begin
  inherited;
  FStatusCode := Value;
end;

end.