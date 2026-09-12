# brand.md — metacognition

Brand guide, 12 Sep 2026. Built from live reads of Vercel, Linear, Raycast, Anthropic and Obsidian
(hex codes read from their CSS today; research file
the research) and from the READMEs of the two
biggest agent-tool repos. Jazz picks the direction; then the deck, the README and the X pictures
follow this file.

## 1. What the brand must do

Make a developer feel two things in three seconds: this is serious, and I am late.
Serious comes from restraint: one accent, real screens, numbers with sources, no adjectives.
Late comes from honest proof: counts that are true today, and a rate that keeps moving while
the reader reads. Cialdini names the levers: social proof, scarcity, authority. Only the honest
forms are allowed here (section 7).

## 2. Name and one line

- Name: **metacognition**, always lowercase, set in the mono face.
- One line: *Your AI reads your rules and ignores them. This measures which ones.*
- Position: an instrument, not an assistant. Proof, not promise.

## 3. Voice

- The number first, then the sentence. "10 of 10 caught. 0 false alarms."
- Counts, dates, exit codes. Never "powerful", "seamless", "AI-powered", "revolutionary".
- Plain English, short sentences, no metaphor. A stranger reads it in one pass.
- Humble about people, exact about the machine. Credit prior work by name (TRACE, agnix).
- Never a claim without a source on the same screen.

## 4. The palette, decided by Jazz on 12 Sep: red, black, white

His words: "use modern color. simple." then "use red black white." Three tokens. Nothing else is coloured.

| Token | Light (README, X pictures, GitHub preview) | Dark (the deck, dark mode) |
|---|---|---|
| background | #FFFFFF, cards #F7F7F7, lines #EBEBEB | #0A0A0A, cards #141414, lines #2A2A2A |
| ink (all text) | #111111, captions #6B7280 | #F2F2F2, captions #8A8F98 |
| red (the one accent): the word RED, the failing rule's underline, the counter | #DC2626 | #FF453A |

- Type: **Inter** for text, **JetBrains Mono** for numbers, commands, verdicts and the name. Both on Google Fonts.
- The mark: no icon in version 1. The mark is one real verdict line in mono, with RED in red and the failing rule underlined in red.
- A pass is a white ring or a check mark in ink. A fail is a red disc. No green anywhere, ever. No gold, no navy, no gradients.
- Reference pictures: `~/Downloads/brand-white.png` and `~/Downloads/brand-black.png` (rendered 12 Sep).
- Rejected on the way, with the reason: navy and gold (none of the five respected brands uses either); red-orange pen #D9480F (read as a warning); blue #2563EB (modern but not his); violet (every AI product); teal (reads as success next to a failed verdict).

## 5. Rejected alternative: Black Box, Opened (near-black, acid flag)

- paper #0A0A0A, ink #E2E4E7, muted #8A8F98, accent #D7FF3D (one acid flag), rule #1F2124.
- Type: Geist + Geist Mono (Vercel's), or Inter + JetBrains Mono if Geist is not available.
- The mark: a grid of grey dots, one lit acid: "the one thing it noticed that you did not".
- Why it loses to A: it looks like Linear and Raycast, so it does not stand out on X, and the
  lit-dot idea is one step from the status lights he already rejected.

## 6. Pictures

1. Always a real screen: a terminal, a verdict, a diff. Never a designed card, never an illustration, never a robot.
2. One red mark per picture: an underline, a circle, or one word. Never two.
3. One plain sentence on the picture, 12 words or fewer. Readable in 3 seconds.
4. One number at most in the sentence. Other numbers stay inside the screenshot.
5. The deck: black stage, white type, red for the fail. The board of lights is a row of white
   rings; the failing rule is a red disc. The macOS window dots are grey, not three colours.

## 7. FOMO rules, honest only

Allowed:
- Real counters on the hero, refreshed from the code: rules checked today, breaks caught,
  corrections that were never typed twice. Omarchy shows "1,102,980 ISO downloads"; the
  GitHub star badge is the standard form. Show only numbers that are true right now.
- The rate line: "one check every 30 minutes, 48 a day, while you sleep."
- The "you saw 0" line: "your agent noticed 4 things this week and acted on 3. You saw 0."
- Time, not seats: "the people who start recording this month will have a year of it by next September."
- Social proof only when it exists: stars, contributors, forks. Zero is shown as zero.

Not allowed:
- Countdown timers, "only N spots", fake scarcity of any kind.
- Claims about other tools without a source and their name.
- "Nobody else does this." Say who does the nearest thing, and what this adds.

## 8. Applications

- README top: one sentence, the star badge, one screenshot of the verdict line, the install line. Nothing above the fold that is not one of those four.
- GitHub social preview (1280x640): paper, the verdict line in mono with the red underline, the name bottom-left.
- X post picture (1200x675): a real terminal screenshot on paper, one red underline, one sentence.
- Deck: same tokens; every slide is a real screen or a drawing of one, red pen for the fail, ink for the rest.

## 9. Do and do not

| Do | Do not |
|---|---|
| lowercase name in mono | capital M, a logo icon, a mascot |
| one accent, red #DC2626 / #FF453A | gold, navy, green, blue, violet, gradients |
| numbers with sources | adjectives, exclamation marks, emoji |
| real screens | illustrations, stock photos, robots, brains |
| white by default, near-black dark mode | mid-tone dark blues or greys |
