# Service status in Settings

The General pane shows one row each for the Background Agent and the
Privileged Helper. Each row carries a symbol, a spoken label, and a status
word. All three come from one value, so they cannot disagree.

## What the Background Agent row reports

| Symbol | Color | Word | Meaning |
| --- | --- | --- | --- |
| Filled check | Green | Running | Registered, and something proves it is answering |
| Filled triangle | Orange | Not responding | Registered, but nothing proves it is answering |
| Hollow circle | Gray | Not Installed | Not registered with Service Management |

The symbol and the word carry the state on their own. Color is a second
channel, never the only one, so the row stays readable in grayscale, with
color blindness, and through VoiceOver.

## What proves the Agent is answering

Three signals can prove it, ranked. The strongest available one decides.

1. **An open XPC connection.** Direct proof: the Agent accepted a connection
   and is serving it. This cannot go stale.
2. **A recent heartbeat.** The Agent writes a timestamp to the shared defaults
   suite once a second, on a timer independent of its tick loop. It counts as
   proof while it is under ten seconds old.
3. **Nothing.** The row reports "Not responding".

Registration and liveness are separate questions. An open connection proves
the Agent is answering. It does not prove the Agent is registered, so it never
makes the row claim the Agent is installed.

## Why the heartbeat is ranked last

The app only learns the heartbeat's value when it polls, every two seconds
while the pane is open. Its age is fixed at the moment of that read, not
recomputed while the view renders.

Measuring the age at render time was a defect. The age then grew whenever the
poll itself ran late, and the row reported a fault that described the app's
own scheduling rather than the Agent. The poll runs in the common run loop
mode so that scrolling the list or dragging the window cannot delay it.

## Transitions are logged

Every change to what the row reports is logged with the state before, the
state after, which signal decided, and the heartbeat's age. A wrong dot is
diagnosable from the log alone.
