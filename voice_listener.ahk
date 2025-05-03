#Warn VarUnset, Off
#Requires AutoHotkey v2.0
#SingleInstance Force

;── Enable per‑monitor DPI awareness ──  
DllCall("SetThreadDpiAwarenessContext", "Ptr", -3)

;── Global config ──  
global listenerPath     := A_ScriptDir "\VoskListener.py"
global commandFile      := A_ScriptDir "\voice_command.txt"
global lastCommand      := ""
global lastAction       := ""
global lastHeardTime    := A_TickCount
global fileStream       ; for streaming new words
global initedStream     := false
global winW             := 700
global winH             := 400
global lastValidMonitor := 1  ; Track last valid monitor
global logOutput        ; Declare globally
global pythonPid        := 0  ; Store Python process ID

;── Functions ──
KillExistingPythonProcesses() {
    terminated := 0
    for process in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name = 'python.exe'")
    {
        if InStr(process.CommandLine, "VoskListener.py")
        {
            ProcessClose(process.ProcessId)
            terminated++
            Sleep 200
        }
    }
    if (terminated > 0)
        Sleep 500
    return terminated
}

KillPythonOnExit() {
    global pythonPid
    if (pythonPid)
        ProcessClose(pythonPid)
}

CheckPythonInstances() {
    count := 0
    for process in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name = 'python.exe'")
        if InStr(process.CommandLine, "VoskListener.py")
            count++
    if (count > 1)
    {
        LogMessage("⚠ $count VoskListener.py instances found, terminating excess")
        KillExistingPythonProcesses()
        Run Format('python.exe "{}"', listenerPath), , "Hide", &pythonPid
    }
}

;── Launch the listener if it exists ──  
if FileExist(listenerPath)
{
    terminated := KillExistingPythonProcesses()
    if (terminated > 1)
        LogMessage("⚠ Terminated $terminated existing VoskListener.py instances")
    Run Format('python.exe "{}"', listenerPath), , "Hide", &pythonPid
    Sleep 1000
    count := 0
    for process in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name = 'python.exe'")
        if InStr(process.CommandLine, "VoskListener.py")
            count++
    if (count > 1)
        LogMessage("⚠ Warning: $count VoskListener.py instances running")
}

;── Create Matrix‑style UI under the cursor ──  
MouseGetPos(&startX, &startY)
monitorCount := MonitorGetCount()
targetM := MonitorGetPrimary()  ; Default to primary monitor
Loop monitorCount {
    MonitorGet(A_Index, &L, &T, &R, &B)
    if (startX >= L && startX < R && startY >= T && startY < B) {
        targetM := A_Index
        lastValidMonitor := targetM
        break
    }
}
MonitorGet(targetM, &L, &T, &R, &B)
startX := Max(L, Min(startX + 20, R - winW))
startY := Max(T, Min(startY + 20, B - winH))

logGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
logGui.BackColor := "Black"
logGui.SetFont("s10 cLime", "Consolas")
logOutput := logGui.Add("Edit", "ReadOnly w" . winW . " r20 -VScroll Border", "")
logGui.Show Format("x{} y{} w{} h{} NoActivate", startX, startY, winW, winH)
WinSetTransparent(180, logGui.Hwnd)

; Log initial monitor selection after GUI creation
LogMessage("Initial monitor $targetM selected for mouse ($startX,$startY)")

;── Start timers ──  
SetTimer(CheckForVoiceCommand, 50)   ; 50 ms polling
SetTimer(UpdateGuiPosition, 100)     ; 100ms for GUI updates
SetTimer(FadeOutLogGui, 1000)
SetTimer(CheckPythonInstances, 60000)  ; Check every 60s
OnExit((*) => KillPythonOnExit())
return

;────────────────────────────────────────────────────
;  Keep the GUI following the mouse and on top
;────────────────────────────────────────────────────
UpdateGuiPosition() {
    global logGui, winW, winH, lastValidMonitor

    ; Get mouse position via MouseGetPos
    MouseGetPos(&mx1, &my1)

    ; Get mouse position via GetCursorPos
    point := Buffer(8, 0)
    if DllCall("GetCursorPos", "Ptr", point) {
        mx2 := NumGet(point, 0, "Int")
        my2 := NumGet(point, 4, "Int")
    } else {
        mx2 := mx1
        my2 := my1
    }

    ; Use MouseGetPos unless it differs significantly
    if (Abs(mx1 - mx2) > 100 || Abs(my1 - my2) > 100) {
        mx := mx2
        my := my2
    } else {
        mx := mx1
        my := my1
    }

    ; Determine which monitor contains the mouse
    monitorCount := MonitorGetCount()
    target := lastValidMonitor
    foundMonitor := false
    Loop monitorCount {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (mx >= L && mx < R && my >= T && my < B) {
            target := A_Index
            lastValidMonitor := target
            foundMonitor := true
            break
        }
    }
    if (!foundMonitor) {
        target := MonitorGetPrimary()
        lastValidMonitor := target
    }
    MonitorGet(target, &L, &T, &R, &B)

    ; Normalize mouse coordinates to monitor's coordinate system
    mx_normalized := mx - L
    my_normalized := my - T

    ; Compute GUI position relative to monitor
    newX := L + mx_normalized + 20
    newY := T + my_normalized + 20
    newX := Max(L, Min(newX, R - winW))
    newY := Max(T, Min(newY, B - winH))

    ; Move GUI
    DllCall("SetWindowPos"
        , "Ptr", logGui.Hwnd
        , "Ptr", -1
        , "Int", newX
        , "Int", newY
        , "Int", 0
        , "Int", 0
        , "UInt", 0x1|0x10
    )

    ; Restore transparency
    WinSetTransparent(180, logGui.Hwnd)
}

;────────────────────────────────────────────────────
;  Read only new words via FileOpen streaming
;────────────────────────────────────────────────────
CheckForVoiceCommand() {
    global commandFile, lastCommand, lastAction, lastHeardTime
    global fileStream, initedStream, logOutput

    ; Initialize fileStream once
    if !initedStream {
        if FileExist(commandFile) {
            fileStream := FileOpen(commandFile, "r")
            fileStream.Seek(0, 2)  ; Go to end
        }
        initedStream := true
    }

    if initedStream {
        newData := fileStream.Read()
        if (newData) {
            for word in StrSplit(Trim(newData), " ")
                if (word) {
                    LogMessage("🗣 " word)
                    lastHeardTime := A_TickCount
                }
        }
    }

    ; Full-phrase detection
    fullText := Trim(FileRead(commandFile))
    if (fullText = "" || fullText = lastCommand)
        return

    lastCommand := fullText
    lastHeardTime := A_TickCount
    WinSetTransparent(180, logGui.Hwnd)

    lower := StrLower(fullText)
    feedback := ""
    if RegExMatch(lower, "^computer\b") {
        if (lower = lastAction) {
            feedback := "⏸ Ignored duplicate command"
        }
        else if RegExMatch(lower, "i)^(?:computer\s+)?exit\b") {
            feedback := "✔ Exiting script"
            LogMessage(feedback)
            Sleep 500
            ExitApp()
        }
        else if RegExMatch(lower, "notepad|note pad|know pad|no pad") {
            SetTimer(UpdateGuiPosition, 0)  ; Disable GUI position updates
            Run "notepad.exe"
            SetTimer(() => SetTimer(UpdateGuiPosition, 100), -750)  ; Resume after 750ms
            lastAction := lower
            feedback := "✔ Opening Notepad"
        }
        else if InStr(lower, "calculator") {
            SetTimer(UpdateGuiPosition, 0)
            Run "calc.exe"
            SetTimer(() => SetTimer(UpdateGuiPosition, 100), -750)
            lastAction := lower
            feedback := "✔ Opening Calculator"
        }
        else if InStr(lower, "browser") {
            SetTimer(UpdateGuiPosition, 0)
            Run "https://www.google.com"
            SetTimer(() => SetTimer(UpdateGuiPosition, 100), -750)
            lastAction := lower
            feedback := "✔ Opening Browser"
        }
        else {
            feedback := "⚠ Unknown command"
        }
    } else {
        feedback := "(No trigger word detected)"
    }

    if (feedback && feedback != "✔ Exiting script")
        LogMessage(feedback)
}

;────────────────────────────────────────────────────
;  Fade out after 5 s of silence
;────────────────────────────────────────────────────
FadeOutLogGui() {
    global logGui, lastHeardTime
    if (A_TickCount - lastHeardTime > 5000)
    {
        WinSetTransparent(40, logGui.Hwnd)
        SetTimer(UpdateGuiPosition, 0)  ; Pause updates
    }
    else
    {
        WinSetTransparent(180, logGui.Hwnd)
        SetTimer(UpdateGuiPosition, 100)  ; Resume updates
    }
}

;────────────────────────────────────────────────────
;  Append a timestamped line and cap at 200 lines
;────────────────────────────────────────────────────
LogMessage(msg) {
    global logOutput

    ; Skip if logOutput is not yet initialized
    if (!IsObject(logOutput))
        return

    ; Timestamp [HH:MM:SS]
    ts := SubStr(A_Now, 9, 2) ":" SubStr(A_Now, 11, 2) ":" SubStr(A_Now, 13, 2)
    newLine := "[" ts "] " msg "`n"
    logOutput.Value .= newLine

    ; Count lines by counting "`n"
    text     := logOutput.Value
    totalLen := StrLen(text)
    noNLLen  := StrLen(StrReplace(text, "`n", ""))
    lines    := totalLen - noNLLen

    ; Prune to last 200 lines
    if (lines > 200) {
        drop := lines - 200
        pos  := 0
        Loop drop
            pos := InStr(text, "`n", false, pos + 1)
        text := SubStr(text, pos + 1)
        logOutput.Value := text
    }

    ; Scroll to bottom
    PostMessage(0x115, 7, 0, logOutput.Hwnd)
}