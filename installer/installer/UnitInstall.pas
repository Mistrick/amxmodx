unit UnitInstall;

interface

uses SysUtils, Classes, Windows, Graphics, Forms, ShellAPI, Controls, Messages,
     TlHelp32, IdFTPCommon, ComCtrls;

type TMod = (modNone, modCS, modDoD, modTFC, modNS, modTS, modESF);
type TOS = (osWindows, osLinux32, osLinux64);

procedure AddStatus(Text: String; Color: TColor; ShowTime: Boolean = True);
procedure AddDone(Additional: String = '');
procedure AddSkipped;
procedure AddNotFound;
function DelDir(Dir: string): Boolean;
procedure MakeDir(Dir: String);
procedure DownloadFile(eFile: String; eDestination: String);

procedure BasicInstallation(ePath: String; eMod: TMod; SteamInstall: Boolean; OS: TOS);
procedure InstallDedicated(eModPath: String; eMod: TMod; UseSteam: Boolean);
procedure InstallListen(ePath: String; eMod: TMod);
procedure InstallCustom(ePath: String; eMod: TMod; eOS: TOS);
procedure InstallFTP(eMod: TMod; OS: TOS);

var StartTime: TDateTime;
    SteamPath: String;
    StandaloneServer: String;
    Cancel: Boolean = False;

    FileList: TStringList;
    DirList: TStringList;

implementation

uses UnitfrmMain, UnitfrmProxy, UnitFunctions, UnitScanMods;

// useful stuff

function InstallTime: String;
begin
  Result := FormatDateTime('HH:MM:SS', Now - StartTime);
end;

procedure AddStatus(Text: String; Color: TColor; ShowTime: Boolean = True);
begin
  frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  if ShowTime then begin
    frmMain.rtfDetails.SelAttributes.Color := clBlack;
    if frmMain.rtfDetails.Text = '' then
      frmMain.rtfDetails.SelText := '[' + InstallTime + '] '
    else
      frmMain.rtfDetails.SelText := #13#10 + '[' + InstallTime + '] ';
    frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  end
  else
    frmMain.rtfDetails.SelText := #13#10;

  frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  frmMain.rtfDetails.SelAttributes.Color := Color;
  frmMain.rtfDetails.SelText := Text;
  frmMain.rtfDetails.Perform(WM_VSCROLL, SB_BOTTOM, 0);

  frmMain.Repaint;
  Application.ProcessMessages;
end;

procedure AddDone(Additional: String = '');
begin
  frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  frmMain.rtfDetails.SelAttributes.Color := clGreen;
  if Additional = '' then
    frmMain.rtfDetails.SelText := ' Done.'
  else
    frmMain.rtfDetails.SelText := ' Done, ' + Additional + '.';
  frmMain.rtfDetails.Perform(WM_VSCROLL, SB_BOTTOM, 0);

  frmMain.Repaint;
  Application.ProcessMessages;
end;

procedure AddSkipped;
begin
  frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  frmMain.rtfDetails.SelAttributes.Color := $004080FF; // orange
  frmMain.rtfDetails.SelText := ' Skipped.';
  frmMain.rtfDetails.Perform(WM_VSCROLL, SB_BOTTOM, 0);

  frmMain.Repaint;
  Application.ProcessMessages;
end;

procedure AddNotFound;
begin
  frmMain.rtfDetails.SelStart := Length(frmMain.rtfDetails.Text);
  frmMain.rtfDetails.SelAttributes.Color := clRed;
  frmMain.rtfDetails.SelText := ' Not found.';
  frmMain.rtfDetails.Perform(WM_VSCROLL, SB_BOTTOM, 0);

  frmMain.Repaint;
  Application.ProcessMessages;
end;

function DelDir(Dir: string): Boolean;
var Fos: TSHFileOpStruct;
begin 
  ZeroMemory(@Fos, SizeOf(Fos)); 
  with Fos do begin 
    wFunc  := FO_DELETE; 
    fFlags := FOF_SILENT or FOF_NOCONFIRMATION; 
    pFrom  := PChar(Dir + #0); 
  end; 
  Result := (ShFileOperation(fos) = 0); 
end;

procedure MakeDir(Dir: String);
begin
  try
    if not DirectoryExists(Dir) then
      ForceDirectories(Dir);
  except
    Application.ProcessMessages;
  end;
end;

procedure FileCopy(Source, Destination: String; CopyConfig: Boolean; AddStatus: Boolean = True);
begin
  if (not CopyConfig) and (Pos('config', Source) <> 0) then begin
    if AddStatus then
      AddSkipped;
    exit;
  end;

  if not FileExists(Source) then begin
    if AddStatus then
      AddNotFound;
    exit;
  end;

  try
    if FileExists(Destination) then
      DeleteFile(PChar(Destination));
    CopyFile(PChar(Source), PChar(Destination), False);
  except
    Application.ProcessMessages;
  end;

  if AddStatus then
    AddDone;
end;

procedure DownloadFile(eFile: String; eDestination: String);
var TransferType: TIdFTPTransferType;
begin
  // much better when files are transfered with the correct transfer type...
  TransferType := ftBinary;
  if ExtractFileExt(LowerCase(eFile)) = '.txt' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.cfg' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.ini' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.sma' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.inc' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.gam' then TransferType := ftASCII;
  if frmMain.IdFTP.TransferType <> TransferType then
    frmMain.IdFTP.TransferType := TransferType;
  // download the file
  frmMain.IdFTP.Get(eFile, eDestination, True);
end;

procedure UploadFile(eFile: String; eDestination: String; CopyConfig: Boolean = True);
var TransferType: TIdFTPTransferType;
begin
  if (Pos('config', eFile) > 0) and (not CopyConfig) then begin
    AddSkipped;
    exit;
  end;
  
  eDestination := StringReplace(eDestination, '\', '/', [rfReplaceAll]);

  // the same as in DownloadFile()
  TransferType := ftBinary;
  if ExtractFileExt(LowerCase(eFile)) = '.txt' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.cfg' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.ini' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.sma' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.inc' then TransferType := ftASCII;
  if ExtractFileExt(LowerCase(eFile)) = '.gam' then TransferType := ftASCII;
  if frmMain.IdFTP.TransferType <> TransferType then
    frmMain.IdFTP.TransferType := TransferType;
  // upload the file
  frmMain.IdFTP.Put(eFile, eDestination);
  AddDone;
end;

procedure FTPMakeDir(eDir: String);
begin
  eDir := StringReplace(eDir, '\', '/', [rfReplaceAll]);
  try
    frmMain.IdFTP.MakeDir(eDir);
  except
    Application.ProcessMessages;
  end;
end;

function FSize(eFile: String): Cardinal;
var eRec: TSearchRec;
begin
  if FindFirst(eFile, faAnyFile, eRec) = 0 then
    Result := eRec.Size
  else
    Result := 0;
end;

function IsForbidden(eFile: String; eOS: TOS): Boolean;
begin
  Result := False;
  case eOS of
    osWindows: begin
      if ExtractFileExt(eFile) = '.so' then
        Result := True;
    end;
    osLinux32: begin
      if ExtractFileExt(eFile) = '.dll' then
        Result := True;
      if ExtractFileExt(eFile) = '.exe' then
        Result := True;

      if Pos('_amd64', ExtractFileName(eFile)) <> 0 then
        Result := True;
    end;
    osLinux64: begin
      if ExtractFileExt(eFile) = '.dll' then
        Result := True;
      if ExtractFileExt(eFile) = '.exe' then
        Result := True;

      if Pos('_i386', ExtractFileName(eFile)) <> 0 then
        Result := True;
    end;
  end;
end;

// stuff for killing processes

function GetProcessID(sProcName: String): Integer;
var
  hProcSnap: THandle;
  pe32: TProcessEntry32;
begin 
  result := -1; 
  hProcSnap := CreateToolHelp32SnapShot(TH32CS_SNAPPROCESS, 0); 
  if hProcSnap = INVALID_HANDLE_VALUE then
    exit; 

  pe32.dwSize := SizeOf(ProcessEntry32);
  if Process32First(hProcSnap, pe32) = true then begin
    while Process32Next(hProcSnap, pe32) = true do begin
      if pos(sProcName, pe32.szExeFile) <> 0then
        result := pe32.th32ProcessID;
    end;
  end;
  CloseHandle(hProcSnap);
end; 

procedure KillProcess(dwProcID: DWORD); 
var 
  hProcess : Cardinal; 
  dw       : DWORD; 
begin 
  hProcess := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE, False, dwProcID);
  TerminateProcess(hProcess, 0);
  dw := WaitForSingleObject(hProcess, 5000);
  case dw of 
    WAIT_TIMEOUT: begin
      CloseHandle(hProcess);
      exit;
    end;
    WAIT_FAILED: begin 
      RaiseLastOSError; 
      CloseHandle(hProcess); 
      exit; 
    end; 
  end; 
  CloseHandle(hProcess); 
end; 

// Installation here

{ Basic Installation }   

procedure BasicInstallation(ePath: String; eMod: TMod; SteamInstall: Boolean; OS: TOS);
var eStr: TStringList;
    i: integer;
    CopyConfig: Boolean;
begin
  AddStatus('Scanning for directories...', clBlack);
  with GetAllFiles(ExtractFilePath(ParamStr(0)) + 'files\*.*', faDirectory, True, True) do begin
    DirList.Text := Text;
    Free;
  end;
  AddDone('found ' + IntToStr(DirList.Count) + ' directories..');
  AddStatus('Scanning for files...', clBlack);
  with GetAllFiles(ExtractFilePath(ParamStr(0)) + 'files\*.*', faAnyFile, True, False) do begin
    FileList.Text := Text;
    Free;
  end;
  AddDone('found ' + IntToStr(FileList.Count) + ' files..');
  AddStatus('', clBlack, False);

  frmMain.ggeAll.MaxValue := DirList.Count + FileList.Count;
  frmMain.ggeItem.MaxValue := DirList.Count;

  if (GetProcessID('Steam.exe') <> -1) and (SteamInstall) then begin
    if MessageBox(frmMain.Handle, 'Steam is still running. It is necersarry to shut it down before you install AMX Mod X. Shut it down now?', PChar(frmMain.Caption), MB_ICONQUESTION + MB_YESNO) = mrYes then begin
      AddStatus('Shutting down Steam...', clBlack, False);
      if GetProcessID('Steam.exe') = -1 then
        AddDone
      else
        KillProcess(GetProcessID('Steam.exe'));
      while GetProcessID('Steam.exe') <> -1 do begin // sure is sure...
        Sleep(50);
        Application.ProcessMessages;
      end;
      AddDone;
    end
    else begin
      Application.Terminate;
      exit;
    end;
  end;

  CopyConfig := True;
  if DirectoryExists(ePath + 'addons\amxmodx') then begin
    case MessageBox(frmMain.Handle, 'An AMX Mod X installation was already detected. If you choose to reinstall, your configuration files will be erased. Click Yes to continue, No to Upgrade, or Cancel to abort the install.', PChar(frmMain.Caption), MB_ICONQUESTION + MB_YESNOCANCEL) of
      mrNo: CopyConfig := False;
      mrCancel: begin
        Application.Terminate;
        exit;
      end;
    end;
  end;

  for i := 0 to DirList.Count -1 do
    DirList[i] := Copy(DirList[i], Length(ExtractFilePath(ParamStr(0))) + 7, Length(DirList[i]));
  for i := 0 to FileList.Count -1 do
    FileList[i] := Copy(FileList[i], Length(ExtractFilePath(ParamStr(0))) + 7, Length(FileList[i]));

  { liblist.gam }
  if not FileExists(ePath + 'liblist.gam') then begin
    if MessageBox(frmMain.Handle, 'The file "liblist.gam" couldn''t be found. Continue installation?', PChar(frmMain.Caption), MB_ICONQUESTION + MB_YESNO) = mrNo then begin
      AddStatus('Installation canceled by user!', clRed, False);
      Screen.Cursor := crDefault;
      Cancel := True;
      exit;
    end;
  end
  else begin
    AddStatus('Editing liblist.gam...', clBlack);
    eStr := TStringList.Create;
    eStr.LoadFromFile(ePath + 'liblist.gam');
    if eStr.IndexOf('gamedll "addons\metamod\dlls\metamod.dll"') = -1 then begin
      for i := 0 to eStr.Count -1 do begin
        if Pos('gamedll', TrimLeft(eStr[i])) = 1 then
          eStr[i] := '//' + eStr[i];
      end;
      eStr.Add('gamedll "addons\metamod\dlls\metamod.dll"');
      eStr.Add('gamedll_linux "addons/metamod/dlls/metamod_i386.so"');
      FileSetAttr(ePath + 'liblist.gam', 0);
      eStr.SaveToFile(ePath + 'liblist.gam');
      FileSetAttr(ePath + 'liblist.gam', faReadOnly); // important for listen servers
      AddDone;
    end
    else
      AddSkipped;
    eStr.Free;
    { create directories }
    AddStatus('Creating directories...', clBlack);
  end;
  // metamod...
  MakeDir(ePath + 'addons');
  MakeDir(ePath + 'addons\amxmodx');
  MakeDir(ePath + 'addons\metamod');
  MakeDir(ePath + 'addons\metamod\dlls');
  // rest...
  for i := 0 to DirList.Count -1 do begin
    if Cancel then
      exit;
      
    if Pos('base', DirList[i]) = 1 then begin
      MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 6, Length(DirList[i])));
      AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 6, Length(DirList[i])), clBlack);
    end;
    case eMod of
      modCS: begin
        if Pos('cstrike', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 9, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 9, Length(DirList[i])), clBlack);
        end;
      end;
      modDoD: begin
        if Pos('dod', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 5, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 5, Length(DirList[i])), clBlack);
        end;
      end;
      modTFC: begin
        if Pos('tfc', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 5, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 5, Length(DirList[i])), clBlack);
        end;
      end;
      modNS: begin
        if Pos('ns', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])), clBlack);
        end;
      end;
      modTS: begin
        if Pos('ts', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])), clBlack);
        end;
      end;
      modESF: begin
        if Pos('esforce', DirList[i]) = 1 then begin
          MakeDir(ePath + 'addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])));
          AddStatus('Created directory: addons\amxmodx\' + Copy(DirList[i], 4, Length(DirList[i])), clBlack);
        end;
      end;
    end;

    frmMain.ggeAll.Progress := i;
    frmMain.ggeItem.Progress := i;
  end;
  frmMain.ggeItem.MaxValue := FileList.Count;
  { copy all files }
  AddStatus('', clBlack, False);
  AddStatus('Copying files...', clBlack);
  for i := 0 to FileList.Count -1 do begin
    if Cancel then
      exit;
      
    if not IsForbidden(FileList[i], OS) then begin
      if Pos('base', FileList[i]) = 1 then begin
        AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 6, Length(FileList[i])), clBlack);
        FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 6, Length(FileList[i])), CopyConfig);
      end;
      
      case eMod of
        modCS: begin
          if Pos('cstrike', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 9, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 9, Length(FileList[i])), CopyConfig);
          end;
        end;
        modDoD: begin
          if Pos('dod', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 5, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 5, Length(FileList[i])), CopyConfig);
          end;
        end;
        modTFC: begin
          if Pos('tfc', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 5, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 5, Length(FileList[i])), CopyConfig);
          end;
        end;
        modNS: begin
          if Pos('ns', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), CopyConfig);
          end;
        end;
        modTS: begin
          if Pos('ts', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), CopyConfig);
          end;
        end;
        modESF: begin
          if Pos('esforce', FileList[i]) = 1 then begin
            AddStatus('Copying file: addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), clBlack);
            FileCopy(ExtractFilePath(ParamStr(0)) + 'files\' + FileList[i], ePath + 'addons\amxmodx\' + Copy(FileList[i], 4, Length(FileList[i])), CopyConfig);
          end;
        end;
      end;
    end;
    frmMain.ggeAll.Progress := frmMain.ggeAll.Progress + 1;
    frmMain.ggeItem.Progress := i;
  end;
  { metamod }
  AddStatus('Copying Metamod...', clBlack);
  FileCopy(ePath + 'addons\amxmodx\dlls\metamod.dll', ePath + '\addons\metamod\dlls\metamod.dll', CopyConfig, False);
  FileCopy(ePath + '\addons\amxmodx\dlls\metamod_i386.so', ePath + '\addons\metamod\dlls\metamod_i386.so', CopyConfig, False);
  FileCopy(ePath + '\addons\amxmodx\dlls\metamod_amd64.so', ePath + '\addons\metamod\dlls\metamod_amd64.so', CopyConfig, False);

  try
    if FileExists(ePath + '\addons\amxmodx\dlls\metamod.dll')      then DeleteFile(PChar(ePath + '\addons\amxmodx\dlls\metamod.dll'));
    if FileExists(ePath + '\addons\amxmodx\dlls\metamod_amd64.so') then DeleteFile(PChar(ePath + '\addons\amxmodx\dlls\metamod_amd64.so'));
    if FileExists(ePath + '\addons\amxmodx\dlls\metamod_i386.so')  then DeleteFile(PChar(ePath + '\addons\amxmodx\dlls\metamod_i386.so'));
  finally
    eStr := TStringList.Create;
    eStr.Add(';;Metamod plugins.ini');
    eStr.Add(';;AMX Mod X ' + VERSION);
    if OS = osWindows then
      eStr.Add('win32   addons\amxmodx\dlls\amxmodx_mm.dll')
    else if OS = osLinux32 then
      eStr.Add('linux   addons/amxmodx/dlls/amxmodx_mm_i386.so')
    else
      eStr.Add('linux   addons/amxmodx/dlls/amxmodx_mm_amd64.so'); 
    eStr.SaveToFile(ePath + 'addons\metamod\plugins.ini');
    eStr.Free;
  end;
  AddDone;

  // finish...
  frmMain.ggeAll.Progress := frmMain.ggeAll.MaxValue;
  frmMain.ggeItem.Progress := frmMain.ggeItem.MaxValue;

  AddStatus('', clBlack, False);
  AddStatus('Finished installation!', clBlack, False);
  frmMain.cmdNext.Enabled := True;
  frmMain.cmdCancel.Hide;

  Screen.Cursor := crDefault;
end;

{ Dedicated Server }

procedure InstallDedicated(eModPath: String; eMod: TMod; UseSteam: Boolean);
begin
  StartTime := Now;
  Screen.Cursor := crHourGlass;
  AddStatus('Starting installation on dedicated server...', clBlack);
  BasicInstallation(eModPath, eMod, UseSteam, osWindows);
end;

{ Listen Server }

procedure InstallListen(ePath: String; eMod: TMod);
begin
  StartTime := Now;
  Screen.Cursor := crHourGlass;
  AddStatus('Starting installation on the listen server...', clBlack);
  BasicInstallation(ePath, eMod, True, osWindows);
end;

{ Custom mod }

procedure InstallCustom(ePath: String; eMod: TMod; eOS: TOS);
begin
  StartTime := Now;
  Screen.Cursor := crHourGlass;
  AddStatus('Starting AMX Mod X installation...', clBlack);
  BasicInstallation(ePath, eMod, False, eOS);
end;

{ FTP }

procedure InstallFTP(eMod: TMod; OS: TOS);
function DoReconnect: Boolean;
begin
  Result := False;
  if MessageBox(frmMain.Handle, 'You have been disconnected due to an error. Try to reconnect?', PChar(Application.Title), MB_ICONQUESTION + MB_YESNO) = mrYes then begin
    try
      frmMain.IdFTP.Connect;
      Result := True;
    except
      MessageBox(frmMain.Handle, 'Failed to reconnect. Installation aborted.', PChar(Application.Title), MB_ICONSTOP);
    end;
  end;
end;

label CreateAgain;
label UploadAgain;
var eStr: TStringList;
    i: integer;
    ePath: String;
    CurNode: TTreeNode;
    CopyConfig: Boolean;
    eGoBack: Boolean;
begin
  frmMain.cmdCancel.Show;
  frmMain.cmdNext.Hide;
  Screen.Cursor := crHourGlass;
  AddStatus('Scanning for directories...', clBlack);
  with GetAllFiles(ExtractFilePath(ParamStr(0)) + 'temp\*.*', faDirectory, True, True) do begin
    DirList.Text := Text;
    Free;
  end;
  AddDone('found ' + IntToStr(DirList.Count) + ' directories..');
  AddStatus('Scanning for files...', clBlack);
  with GetAllFiles(ExtractFilePath(ParamStr(0)) + 'temp\*.*', faAnyFile, True, False) do begin
    FileList.Text := Text;
    Free;
  end;
  AddDone('found ' + IntToStr(FileList.Count) + ' files..');
  AddStatus('', clBlack, False);

  frmMain.ggeAll.MaxValue := DirList.Count + FileList.Count;
  frmMain.ggeItem.MaxValue := DirList.Count;

  for i := 0 to DirList.Count -1 do
    DirList[i] := Copy(DirList[i], Length(ExtractFilePath(ParamStr(0))) + 6, Length(DirList[i]));
  for i := 0 to FileList.Count -1 do
    FileList[i] := Copy(FileList[i], Length(ExtractFilePath(ParamStr(0))) + 6, Length(FileList[i]));

  // liblist.gam
  CopyConfig := True;
  AddStatus('Editing liblist.gam...', clBlack);
  eStr := TStringList.Create;
  eStr.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'temp\liblist.gam');
  if eStr.IndexOf('gamedll "addons\metamod\dlls\metamod.dll"') = -1 then begin
    if Cancel then
      exit;

    for i := 0 to eStr.Count -1 do begin
      if Pos('gamedll', TrimLeft(eStr[i])) = 1 then
        eStr[i] := '//' + eStr[i];
    end;
    if frmMain.optWindows.Checked then
      eStr.Add('gamedll "addons\metamod\dlls\metamod.dll"')
    else if frmMain.optLinux32.Checked then
      eStr.Add('gamedll_linux "addons/metamod/dlls/metamod_i386.so"')
    else
      eStr.Add('gamedll_linux "addons/metamod/dlls/metamod_amd64.so"');
    FileSetAttr(ExtractFilePath(ParamStr(0)) + 'temp\liblist.gam', 0);
    eStr.SaveToFile(ExtractFilePath(ParamStr(0)) + 'temp\liblist.gam');
  end
  else begin
    case MessageBox(frmMain.Handle, 'An AMX Mod X installation was already detected. If you choose to reinstall, your configuration files will be erased. Click Yes to continue, No to Upgrade, or Cancel to abort the install.', PChar(frmMain.Caption), MB_ICONQUESTION + MB_YESNOCANCEL) of
      mrNo: CopyConfig := False;
      mrCancel: begin
        Application.Terminate;
        exit;
      end;
    end;
  end;
  
  eStr.Free;
  AddDone;

  ePath := '/';
  CurNode := frmMain.trvDirectories.Selected;
  repeat
    ePath := '/' + CurNode.Text + ePath;
    CurNode := CurNode.Parent;
  until (not Assigned(CurNode));

  { create directories }
  AddStatus('Creating directories...', clBlack);   
  // rest...
  for i := 0 to DirList.Count -1 do begin
    if Cancel then
      exit;

    AddStatus('Creating directory: ' + DirList[i], clBlack);
    CreateAgain:
    try
      eGoBack := False;
      FTPMakeDir(ePath + DirList[i]);
    except
      on E: Exception do begin
        if Cancel then exit;

        if frmMain.IdFTP.Connected then begin
          if MessageBox(frmMain.Handle, PChar('An error occured while creating "' + FileList[i] + '"!' + #13 + E.Message + #13 + #13 + 'Retry?'), PChar(Application.Title), MB_ICONSTOP + MB_YESNO) = mrYes then
            eGoBack := True
          else begin
            Screen.Cursor := crDefault;
            Application.Terminate;
            exit;
          end;
        end
        else if not DoReconnect then
          exit
        else
          eGoBack := True;
      end;
    end;
    
    if eGoBack then
      goto CreateAgain;  

    AddDone;
    
    frmMain.ggeAll.Progress := i;
    frmMain.ggeItem.Progress := i;
  end;
  { upload files }
  frmMain.tmrSpeed.Enabled := True;
  AddStatus('', clBlack, False);
  AddStatus('Uploading files...', clBlack);
  AddStatus('', clBlack, False);
  for i := 0 to FileList.Count -1 do begin
    if Cancel then
      exit;

    if not IsForbidden(FileList[i], OS) then begin
      AddStatus('Uploading file: ' + FileList[i], clBlack);
      if FileExists(ExtractFilePath(ParamStr(0)) + 'temp\' + FileList[i]) then begin
        frmMain.ggeItem.MaxValue := FSize(ExtractFilePath(ParamStr(0)) + 'temp\' + FileList[i]);
        UploadAgain:
        try
          eGoBack := False;

          if FileList[i] = 'liblist.gam' then
            frmMain.IdFTP.Site('CHMOD 744 liblist.gam');

          UploadFile(ExtractFilePath(ParamStr(0)) + 'temp\' + FileList[i], ePath + FileList[i], CopyConfig);

          if FileList[i] = 'liblist.gam' then
            frmMain.IdFTP.Size('CHMOD 444 liblist.gam');
        except
          on E: Exception do begin
            if Cancel then exit;

            if frmMain.IdFTP.Connected then begin
              if MessageBox(frmMain.Handle, PChar('An error occured while uploading "' + FileList[i] + '"!' + #13 + E.Message + #13 + #13 + 'Retry?'), PChar(Application.Title), MB_ICONSTOP + MB_YESNO) = mrYes then
                eGoBack := True
              else begin
                Screen.Cursor := crDefault;
                Application.Terminate;
                exit;
              end;
            end
            else if not DoReconnect then
              exit
            else
              eGoBack := True;
          end;
        end;

        if eGoBack then
          goto UploadAgain;
      end
      else
        AddNotFound;
    end;
    frmMain.ggeAll.Progress := frmMain.ggeAll.Progress + 1;
    frmMain.ggeItem.Progress := 0;
  end;
  frmMain.ggeAll.Progress := frmMain.ggeAll.MaxValue;
  frmMain.ggeItem.Progress := frmMain.ggeItem.MaxValue;

  AddStatus('', clBlack, False);
  AddStatus('Finished installation!', clBlack, False);
  DelDir(ExtractFilePath(ParamStr(0)) + 'temp');
  frmMain.tmrSpeed.Enabled := False;

  Screen.Cursor := crDefault;
  frmMain.cmdNext.Enabled := True;
  frmMain.cmdCancel.Hide;
  frmMain.cmdNext.Show;
  frmMain.tmrSpeed.Enabled := False;
  frmMain.Caption := Application.Title;
end;

end.
