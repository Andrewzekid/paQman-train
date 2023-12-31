﻿; (C) Copyright 2021, Bartlomiej Uliasz
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
; http://www.apache.org/licenses/LICENSE-2.0
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; Executes commands in system Shell, and eventually returns stream output
; Execute with empty/no command to close the created background console.
; Modes:
; 1 - Invisible direct execution
; 2 - Invisible execution within new 'cmd' process (use this one if you
;     redirect input/output stream in your command using '>', '|' or '<'
;     operators). StdOut/StdErr in function returned object will be empty after
;     normal execution but errors will throw an exception. If you need output
;     please redirect StdOut with '>' in command so that you can verify it.
; 3 - Visible 'cmd' execution. It is the slowest one, but the only that allows
;     user to view console's live output and eventually input manually if
;     needed.
ExecuteCommand(command:="", mode:=1, admin:=false) {
	static hCon:="", cPid:=""

	if (command == "") {
		FreeConsole()
		return
	}

	if (mode > 1) {
		command := A_ComSpec " /U /V:ON /C `"" command "`""
	}

	if (mode == 3) {
		FreeConsole()

		if (DEBUG_MODE) {
			; MsgBox "Executing: " command
			command .= " || ( echo 1 > twg_cmd_err ) & pause"
		} else {
			command .= " || ( echo 1 > twg_cmd_err & pause )"
		}

		RunWait((admin ? "*RunAs " : "") command)

		if (FileExist("twg_cmd_err")) {
			FreeConsole()
			FileDelete("twg_cmd_err")
			throw Error("Command execution was interrupted by a user or exited with an error. Details were shown in the console window.")
		}

		return
	}

	if (admin) {	; Need to reattach console as administrator
		FreeConsole()
	}
	AttachConsole()

	objShell := ComObject("WScript.Shell")
	try {
		objExec := objShell.Exec(command)
	} catch Error as e {
		errMsg := "Received exception during exeution of command: '" command "'."
			. "`nException: " e.Message
		extraMsg := DescribeException(e)
		FreeConsole()
		throw Error(errMsg, -1, extraMsg)
	}

	stdOut := stdErr := ""

	objExec.StdIn.Close()

	while (!objExec.StdErr.AtEndOfStream) {
		stdErr := objExec.StdErr.ReadAll()
	}
	while (!objExec.StdOut.AtEndOfStream) {
		stdOut .= objExec.StdOut.ReadAll()
	}
	if (admin) {	; Free console to prevent running next commands as Administrator
		FreeConsole()
	}

	; MsgBox A_ThisFunc ":" A_LineNumber ": PID=" objExec.ProcessID " Status=" objExec.Status " ExitCode=" objExec.ExitCode " LE=" A_LastError

	if (objExec.ExitCode) {
		errMsg := "Received " objExec.ExitCode " exit code for command: " command
		extraMsg := ""
		if (StdErr) {
			errMsg .= "`n`n" StdErr
			extraMsg := StdOut
		} else if (StdOut) {
			errMsg .= "`n`n" StdOut
		}
		FreeConsole()
		throw Error(errMsg, -1, extraMsg)
	}

	if (DEBUG_MODE) {
		DebugMessage(command, StdErr, StdOut)
	}
	return {StdOut: stdOut, StdErr: stdErr}


	AttachConsole() {
		if (cPid) {
			return	; a console is already attached
		}

		DetectHiddenWindows True
		if (admin) {
			Run("*RunAs " A_ComSpec " /k",, "Hide", &cPid)
		} else {
			Run(A_ComSpec " /k",, "Hide", &cPid)
		}
		WinWait("ahk_pid " cPid,, 10)
		DllCall("AttachConsole", "UInt", cPid)
		hCon := DllCall("CreateFile",
			"Str", "CONOUT$",
			"UInt", 0xC0000000,
			"UInt", 7,
			"UInt", 0,
			"UInt", 3,
			"UInt", 0,
			"UInt", 0
		)
	}

	FreeConsole() {
		if (!hCon) {
			return
		}
		DllCall("CloseHandle", "uint", hCon)
		DllCall("FreeConsole")
		ProcessClose(cPid)
		hCon := cPid := ""
	}
}

OnExit((*)=>ExecuteCommand())	; terminate console if necessary on script exit

DebugMessage(command, stdErr, stdOut) {
	debugMessageGui := Gui("+Resize +AlwaysOnTop", PROGRAM_TITLE " - Debug Mode")

	debugMessageGui.Add("Text", "section xm w115", "Command executed:")
	commandEdit := debugMessageGui.Add("Edit", "W600 R2 +ReadOnly")
	commandEdit.Value := command

	debugMessageGui.Add("Text", "section xm w115", "StdErr:")
	stdErrEdit := debugMessageGui.Add("Edit", "W600 R10 +ReadOnly")
	stdErrEdit.Value := stdErr

	stdOutLabel := debugMessageGui.Add("Text", "section xm w115", "StdOut:")
	stdOutEdit := debugMessageGui.Add("Edit", "W600 R10 +ReadOnly")
	stdOutEdit.Value := stdOut

	okBtn := debugMessageGui.Add("Button", "Default xm w115", "&OK")
	okBtn.OnEvent("Click", DebugMessage_Close)

	debugMessageGui.OnEvent("Size", DebugMessage_Size)
	debugMessageGui.OnEvent("Close", DebugMessage_Close)
	debugMessageGui.OnEvent("Escape", DebugMessage_Close)
	debugMessageGui.Show()
	WinWaitClose(debugMessageGui.hwnd)

	DebugMessage_Close(*) {
		debugMessageGui.Destroy()
	}

	DebugMessage_Size(thisGui, minMax, width, height) {
		if (minMax == -1) {
			return
		}
		commandEdit.Move(,, width-20,)
		stdErrEdit.Move(,, width-20, height//2 - 75)
		stdOutLabel.Move(, height//2 + 13)
		stdOutEdit.Move(, height//2 + 33, width-20, height//2 - 75)
		okBtn.Move(,height - 30)
	}
}
