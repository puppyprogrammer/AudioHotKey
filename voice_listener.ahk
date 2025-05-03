#Warn  VarUnset, Off
#Requires AutoHotkey v2.0
#SingleInstance Force

DllCall("SetThreadDpiAwarenessContext", "Ptr", -3)
CoordMode "Mouse", "Screen"          ; always use screen coords

;── Globals ──
global listenerExe    := A_ScriptDir '\VoskListener.exe'
global listenerPy     := A_ScriptDir '\VoskListener.py'
global commandFile    := A_ScriptDir '\voice_command.txt'
global configFile     := A_ScriptDir '\commands.txt'
global customCommands := []
global lastCommand    := ''
global lastAction     := ''
global lastHeardTime  := A_TickCount
global fileStream, initedStream := false
global winW := 200, winH := 60
global logGui, logOutput := ''
global heardLine                       ; NEW: single‑line debug display
global pyPid := 0
global freezeUntil := 0                ; overlay “freeze” timer (ms)

FreezeOverlay(ms := 300) {
    global freezeUntil
    freezeUntil := A_TickCount + ms
}

;── Load commands.txt ──
if !FileExist(configFile) {
    MsgBox 'commands.txt not found:`n' configFile
    ExitApp
}
for line in StrSplit(FileRead(configFile), '`n', '`r') {
    line := Trim(line)
    if (line = '' || SubStr(line,1,1) = '#')
        continue
    parts := StrSplit(line, '|')
    if parts.Length < 2
        continue
    customCommands.Push({
        trigger: StrLower(Trim(parts[1])),
        type:    Trim(parts[2]),
        data:    parts.Length >= 3 ? Trim(parts[3]) : ''
    })
}

;── Launch listener ──
if FileExist(listenerExe) {
    Run listenerExe, , "Hide", &pyPid
} else if FileExist(listenerPy) {
    Run Format('"python.exe" "%s"', listenerPy), , "Hide", &pyPid
} else {
    MsgBox '❌ Neither VoskListener.exe nor VoskListener.py found.'
    ExitApp
}

if !ProcessWait(pyPid, 5)
    LogMessage('⚠ Listener failed to start in 5000 ms')
else
    LogMessage('✔ Listener started (PID ' pyPid ')')

;── Build overlay UI ──
MouseGetPos &startX, &startY
monitorCount := MonitorGetCount(), monitor := MonitorGetPrimary()
Loop monitorCount {
    MonitorGet(A_Index,&L,&T,&R,&B)
    if (startX>=L && startX<R && startY>=T && startY<B) {
        monitor := A_Index
        break
    }
}
MonitorGet(monitor,&L,&T,&R,&B)
startX := Max(L, Min(startX+20, R-winW))
startY := Max(T, Min(startY+20, B-winH))

logGui := Gui('+AlwaysOnTop -Caption +ToolWindow +E0x80000')
logGui.BackColor := 'Black'
logGui.SetFont('s6 cLime', 'Consolas')

heardLine := logGui.AddText(                                ; NEW
    'x4 y2 w' winW-8 ' h10 BackgroundBlack cYellow'
  , 'Heard:')

logOutput := logGui.AddEdit(
      'ReadOnly '
    . 'x0 y12 w' winW ' h' winH-12 ' '                   ; shifted down
    . '-VScroll -Border -E0x200 '
    . 'BackgroundBlack cLime', '')

logGui.Show('x' startX ' y' startY ' w' winW ' h' winH ' NoActivate')
WinSetTransparent(180, logGui.Hwnd)
LogMessage('Initial monitor ' monitor ' @(' startX ',' startY ')')

;── Timers & cleanup ──
SetTimer CheckForVoiceCommand, 50
SetTimer UpdateGuiPosition,    50
SetTimer FadeOutLogGui,       1000

cleanup(*) {
    if (pyPid)
        ProcessClose(pyPid)
    return 0
}
OnExit cleanup
return

;────────────────────────────────────────────────────
CheckForVoiceCommand() {
    global fileStream, initedStream, commandFile, lastCommand, lastHeardTime, heardLine

    if !initedStream && FileExist(commandFile) {
        fileStream := FileOpen(commandFile, 'r')
        fileStream.Seek(0, 2)      ; jump to EOF
        initedStream := true
    }

    if initedStream {
        for word in StrSplit(Trim(fileStream.Read()), ' ')
            if word {
                LogMessage('🗣 ' word)
                lastHeardTime := A_TickCount
            }
    }

    fullText := Trim(FileRead(commandFile))
    if (fullText = '' || fullText = lastCommand)
        return

    heardLine.Text := 'Heard: ' fullText          ; NEW live feedback
    lastCommand := fullText
    lastHeardTime := A_TickCount
    ProcessVoiceCommand(fullText)
}

ProcessVoiceCommand(text) {
    global customCommands, lastAction
    for cmd in customCommands {
        if (StrLower(text) = cmd.trigger) {
            if (text = lastAction)
                return
            lastAction := text
            switch cmd.type {
                case 'run':
                    FreezeOverlay(500)
                    Run cmd.data
                    LogMessage('✔ Launched ' cmd.data)
                case 'send':
                    FreezeOverlay(300)
                    Send cmd.data
                    LogMessage('✔ Sent ' cmd.data)
                case 'exit':
                    FreezeOverlay(300)
                    LogMessage('✔ Exiting')
                    Sleep 200
                    ExitApp
                default:
                    LogMessage('⚠ Unknown type: ' cmd.type)
            }
            return
        }
    }
}

UpdateGuiPosition() {
    global logGui, winW, winH, freezeUntil
    if (A_TickCount < freezeUntil)
        return

    MouseGetPos &mx,&my
    monitorCount := MonitorGetCount(), monitor := MonitorGetPrimary()
    Loop monitorCount {
        MonitorGet(A_Index,&L,&T,&R,&B)
        if (mx>=L && mx<R && my>=T && my<B) {
            monitor := A_Index
            break
        }
    }
    MonitorGet(monitor,&L,&T,&R,&B)
    newX := Max(L, Min(mx+20, R-winW))
    newY := Max(T, Min(my+20, B-winH))

    static lastX := -1, lastY := -1
    if (newX != lastX || newY != lastY) {
        DllCall('SetWindowPos','Ptr',logGui.Hwnd,'Ptr',-1
            ,'Int',newX,'Int',newY,'Int',0,'Int',0,'UInt',0x1|0x10)
        lastX := newX, lastY := newY
    }
}

FadeOutLogGui() {
    global logGui, lastHeardTime
    WinSetTransparent((A_TickCount - lastHeardTime > 5000) ? 40 : 180, logGui.Hwnd)
}

LogMessage(msg) {
    global logOutput
    if !IsObject(logOutput)
        return
    ts := FormatTime(, 'HH:mm:ss')
    line := '[' ts '] ' msg '`n'
    logOutput.Value .= line

    while (StrSplit(logOutput.Value, '`n').Length > 200)
        logOutput.Value := SubStr(logOutput.Value, InStr(logOutput.Value,'`n')+1)

    PostMessage 0x115, 7, 0, logOutput.Hwnd   ; scroll to bottom
}
