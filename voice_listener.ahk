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
global winW             := 200
global winH             := 50
global lastValidMonitor := 1   ; Track last valid monitor
global logGui, logOutput      ; GUI and its Edit control
global pythonPid        := 0   ; Store Python process ID

;── Create Matrix‑style UI under the cursor ──
MouseGetPos(&startX, &startY)
monitorCount := MonitorGetCount()
targetM := MonitorGetPrimary()
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
logGui.SetFont("s6 cLime", "Consolas")  ; smaller text

; Edit control: ReadOnly, black background, lime text, no border, no client edge
logOutput := logGui.Add(
    "Edit"
    , "ReadOnly w" . winW . " h" . winH
      . " -VScroll -Border -E0x200 BackgroundBlack cLime"
    , ""
)

logGui.Show Format("x{} y{} w{} h{} NoActivate", startX, startY, winW, winH)
WinSetTransparent(180, logGui.Hwnd)


;── Initial log entry ──
LogMessage("Initial monitor " targetM " selected at (" startX "," startY ")")

;── Functions ──
KillExistingPythonProcesses() {
    terminated := 0
    for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name='python.exe'") {
        if InStr(proc.CommandLine, "VoskListener.py") {
            ProcessClose(proc.ProcessId)
            terminated++
            Sleep 200
        }
    }
    if (terminated)
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
    for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name='python.exe'") {
        if InStr(proc.CommandLine, "VoskListener.py")
            count++
    }
    if (count > 1) {
        LogMessage("⚠ " count " VoskListener.py instances found, killing excess")
        KillExistingPythonProcesses()
        Run Format('python.exe "{}"', listenerPath), , "Hide", &pythonPid
    }
}

;── Launch the listener if it exists ──
if FileExist(listenerPath) {
    term := KillExistingPythonProcesses()
    if (term > 1)
        LogMessage("⚠ Terminated " term " stale listener(s)")

    Run Format('python.exe "{}"', listenerPath), , "Hide", &pythonPid

    ; wait up to 5 s for the Python process to start
    timeout := 5000
    elapsed := 0
    while (elapsed < timeout) {
        if ProcessExist(pythonPid)
            break
        Sleep 100
        elapsed += 100
    }
    if !ProcessExist(pythonPid)
        LogMessage("⚠ Listener failed to start in " timeout "ms")

    ; wait up to 5 s for the commandFile to be created
    elapsed := 0
    while (elapsed < timeout) {
        if FileExist(commandFile)
            break
        Sleep 100
        elapsed += 100
    }
    if !FileExist(commandFile)
        LogMessage("⚠ commandFile not created in " timeout "ms")

    ; clear any leftover command so “exit” isn’t re‑triggered on startup
    if FileExist(commandFile) {
        FileDelete(commandFile)
        FileAppend "", commandFile
    }
    lastCommand := ""

    Sleep 1000
    LogMessage("✔ Python listener up (PID " pythonPid ")")
}


;── Start timers and cleanup ──
SetTimer(CheckForVoiceCommand, 50)
SetTimer(UpdateGuiPosition,   100)
SetTimer(FadeOutLogGui,       1000)
SetTimer(CheckPythonInstances,60000)
OnExit((*) => KillPythonOnExit())
return

;────────────────────────────────────────────────────
; Keep the GUI following the mouse and on top
;────────────────────────────────────────────────────
UpdateGuiPosition() {
    global logGui, winW, winH, lastValidMonitor

    MouseGetPos(&mx, &my)
    monitorCount := MonitorGetCount()
    target := lastValidMonitor
    Loop monitorCount {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (mx>=L && mx<R && my>=T && my<B) {
            target := A_Index
            lastValidMonitor := target
            break
        }
    }
    MonitorGet(target, &L, &T, &R, &B)

    newX := Max(L, Min(mx+20, R-winW))
    newY := Max(T, Min(my+20, B-winH))

    DllCall("SetWindowPos"
        , "Ptr", logGui.Hwnd
        , "Ptr", -1
        , "Int", newX
        , "Int", newY
        , "Int", 0
        , "Int", 0
        , "UInt", 0x1|0x10
    )
    WinSetTransparent(180, logGui.Hwnd)
}

;────────────────────────────────────────────────────
; Stream new words and fire commands
;────────────────────────────────────────────────────
CheckForVoiceCommand() {
    global commandFile, lastCommand, lastAction, lastHeardTime
    global fileStream, initedStream, logOutput

    if !initedStream {
        if FileExist(commandFile) {
            fileStream := FileOpen(commandFile, "r")
            fileStream.Seek(0, 2)
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

    fullText := Trim(FileRead(commandFile))
    if (fullText = "" || fullText = lastCommand)
        return
    lastCommand := fullText
    lastHeardTime := A_TickCount
    WinSetTransparent(180, logGui.Hwnd)

    lower := StrLower(fullText), feedback := ""
    if RegExMatch(lower, "i)^computer\b") {
        if (lower = lastAction) {
            feedback := "⏸ Ignored duplicate"
        }
        else if RegExMatch(lower, "i)^(?:computer\s+)?exit\b") {
            feedback := "✔ Exiting script"
            LogMessage(feedback)
            Sleep 500
            ExitApp()
        }
        else if RegExMatch(lower, "i)notepad|note pad") {
            Run "notepad.exe"
            lastAction := lower
            feedback := "✔ Opening Notepad"
        }
        else if InStr(lower, "calculator") {
            Run "calc.exe"
            lastAction := lower
            feedback := "✔ Opening Calculator"
        }
        else if InStr(lower, "browser") {
            Run "https://www.google.com"
            lastAction := lower
            feedback := "✔ Opening Browser"
        }
        else {
            feedback := "⚠ Unknown command"
        }
    } else {
        feedback := "(No trigger word)"
    }
    if feedback
        LogMessage(feedback)
}

;────────────────────────────────────────────────────
; Fade out after 5 s of silence
;────────────────────────────────────────────────────
FadeOutLogGui() {
    global logGui, lastHeardTime
    if (A_TickCount - lastHeardTime > 5000)
        WinSetTransparent(40, logGui.Hwnd)
    else
        WinSetTransparent(180, logGui.Hwnd)
}

;────────────────────────────────────────────────────
; Append a timestamped line and cap at 200 lines
;────────────────────────────────────────────────────
LogMessage(msg) {
    global logOutput
    ts := SubStr(A_Now,9,2) ":" SubStr(A_Now,11,2) ":" SubStr(A_Now,13,2)
    newLine := "[" ts "] " msg "`n"
    logOutput.Value .= newLine

    text := logOutput.Value
    total := StrLen(text)
    noNL := StrLen(StrReplace(text, "`n", ""))
    lines := total - noNL
    if (lines > 200) {
        drop := lines - 200, pos := 0
        Loop drop
            pos := InStr(text, "`n", false, pos+1)
        logOutput.Value := SubStr(text, pos+1)
    }
    PostMessage(0x115, 7, 0, logOutput.Hwnd)
}
