program SakuraPark;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms,
  umain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Title := 'Sakura Lake Park';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
