VAR accepted_borrowed_light = false
VAR borrowed_light_ending = ""
VAR knows_lead = false
VAR knows_kindling = false
VAR knows_about_story = false
VAR knows_proofs_page = false
VAR knows_wren = false
VAR found_story = false
VAR read_borrowed_light = false
VAR knows_proofs_page_survived = false
VAR found_other_wren_pieces = false
VAR talked_to_linnea = false
VAR voiced_recognition = false
VAR linnea_knows_cass_seeks = false
VAR cass_read_story = false

-> journal

=== cass ===
Cass looks up before you've reached the counter and laughs - warm, easy, half a beat before you've said anything worth laughing at. It lands anyway. For a second you feel like the most interesting person who's walked in all week.
{ borrowed_light_ending != "": -> quest_complete }
{ accepted_borrowed_light && found_story == false: -> quest_progress }
{ accepted_borrowed_light && found_story: -> end_game }
{ not cass_opening: "There you are," he says, as if he's been waiting all day. "Sit. Actually - don't sit. I need to ask you something, and I need you on my side first." } // skip the next line if you're a returned visitor

// Options (opening state):
- (cass_opening)
* [Ask what he needs.]
    He leans in. "You know Linnea? Used to. We grew up two streets apart. Then - life. You blink and it's twenty years." A small shrug, not quite light. "She's back in town. So am I. And I keep not knocking on her door."
    "She wrote, when we were kids. Properly wrote - had a piece in the school magazine, the real thing. I want to find it. Turn up with it and say: look. I always knew."
    - - (cass_ask_what_he_needs_information_gathering)
    * * [Ask what the story was about.]
        ~ knows_about_story = true
        "No idea." He grins. "Never read it. That's half the point - I want to find it out the same moment she remembers it." -> cass_ask_what_he_needs_information_gathering 
        #(quietly devastating in hindsight; the player won't feel it yet)
    * * [Ask where to start looking.]
        ~ knows_lead = true
        ~ knows_kindling = true
        "The school magazine. What was it called - _Kindling_? Something warm like that." He frowns. "Wendell would know. Ran the printing, kept everything. Try the Old Press." -> cass_ask_what_he_needs_information_gathering
    * * [Ask about Linnea.]
        ~ knows_about_story = true
        "Quiet. Sharp. Saw things the rest of us walked straight past." A pause. "We didn't fall out. We just... stopped. I think that was mostly me." -> cass_ask_what_he_needs_information_gathering // (plants her perceptiveness - the trait the story weaponizes)
    * * [Tell him you'll look into it.]
            "Quietly, though." He's already half-smiling again. "If she hears I've been digging, it ruins the whole thing."
            ~ accepted_borrowed_light = true
            -> END
* [Ask about the shop.]
    "Take one, leave one." He nods at the card by the till. "People bring me what they've finished, take whatever catches them. Half my stock walked in off the street." He glances round the bowed shelves, fond. "Doesn't pay. But I know everyone in town by what they read, which is better than money."
    -> cass_opening
+ Order a coffee. // # (graceful exit - leaves the door open, no dead end)
    Here you go
- -> END

= quest_progress
Cass glances up, hopeful, reads your face, and softens. "Still looking. No - don't apologise, I can see you're on it." The warmth, undimmed. "Take the time. I've waited twenty years; I can wait for a good job done."
-> END

= end_game
Cass is at the counter, and he sees your face and lights up before you've said a word - that half-beat-early warmth, landing the way it always lands. *(if `read_borrowed_light`:* You catch the timing of it now. You can't quite un-see it.*)*
"You found something. I can tell." He sets down the cloth. "Tell me, show me, I don't care which - I've been waiting like a kid at a window."

* [Show him the story]
    ~ cass_read_story = true
    ~ borrowed_light_ending = "A"
    You turn the page to him. *Borrowed Light*, by Wren. His whole face opens - "you *found* it, this is-"
    And then he reads it. You watch it happen: the delight holding, holding, and then not. He reads it twice; you can tell, his eyes go back to the top. "Huh," he says at last, soft. "She was always the one who really looked. The rest of us just talked." He's still smiling, but it's gone somewhere that costs him to keep. "Thank you. Really - I mean it."
    He means it. That's almost the worst part. He folds the warmth back into place - the same easy motion as the laugh - and doesn't quite meet your eye again.
    -> END
* { talked_to_linnea && read_borrowed_light } [Tell him everything, then show him]
    ~ cass_read_story = true
    ~ borrowed_light_ending = "B"
    You tell him first. Before you show him anything - sixteen-year-old Linnea, the thing she wrote and then couldn't live with, her standing over a screen twenty years ago watching it come down. So that when he reads it - and he should; it's his - he reads it already knowing how it ends.
    Then you show him. He reads slowly. The delight goes the same as it would have anyway; there's no version where it doesn't hurt. But it lands different with your words around it.
    "She took it down," he says. "Sixteen, and she was protecting me. From her." A laugh, real this time, wet at the edges. "That's so *her*. Twenty years and I never knew." He looks at you. "Is she still here? Where is she?" And there's something in it that isn't the easy warmth - something that costs him.
    -> END
* { read_borrowed_light } [Tell him you couldn't find it]
    ~ borrowed_light_ending = "C"
    "I looked," you say. "I really looked. Whatever was there - it's gone."
    It isn't gone. It's a click away on a machine in the Reading Room and it will outlast all of you. But you watch the hope go out of him, gently, and you let it. "Ah." He nods, takes it well, the way he takes everything well. "Worth a try. Thank you for looking - honestly." The laugh comes back, a little dimmer. "Maybe some things are meant to stay lost."
    He doesn't know how right he is. You do. You carry it out of the shop, and it's heavier than you expected - the weight of a thing you decided someone was better off not knowing.
    -> END
* { found_other_wren_pieces } [Show him a different story]
    ~ borrowed_light_ending = "E"
    "I found her," you tell him. "Not the one you meant. I found *her*." You bring up the dog story - the mutt who reviews the town's bins, four stars to the butcher's, nil to the chemist's. Wren, sixteen, being funny on purpose.
    Cass reads it and laughs - the real one, the one that arrives *after* the joke, that you've maybe not heard from him before. "Oh, that's *awful*," he says, delighted. "Four stars for the butcher's. She was always-" He shakes his head, grinning. "This is perfect. Better than whatever heavy thing I was bracing for. Knowing me."
    He has what he came for: proof she was real, that they were real, that the kid who wrote this was worth missing. None of the wound. You leave the other story where it is.
    -> END
+ [Give me a little longer]
    "Course. It's kept this long, it'll keep another day. Go on." And he means that too.
    -> END

= quest_complete 
"Thank you for your help"
-> END



=== wendell ===
Wendell shuts the press down to half-speed before he turns round - a courtesy, so he can hear you. Hands wiped on a rag that's long past helping.
{ knows_lead: "Let me guess. Cass sent you." A snort, not unkind. "He still gets other people to do his knocking." }
{ not knows_lead: "Lost, or curious? Either's fine. Both's better." }
-(wendell_opening)
* [Ask about the Old Press]
    "Forty years of jobbing work. Parish newsletters, auction bills, wedding orders-of-service." He pats the idle machine like a horse. "And the school magazine, every term, for nothing. That one I'd have paid *them* to keep doing."
    -> wendell_opening
* [Ask about { knows_kindling: *Kindling* | the school magazine }]
    ~ knows_kindling = true
    "*Kindling*." He says it the way some men say a daughter's name. "The school magazine. We set and ran it here, every term for - eleven years? Twelve. Kids wrote better than half the adults I printed for." A shrug. "School cut it for money reasons. There's always a money reason."
    -> wendell_opening
* { accepted_borrowed_light } [Ask about Linnea's story]
    { not knows_lead } "Now there's a question I haven't been asked in a long while. Who's been talking?"
    ~ knows_wren = true
    "Linnea." He thinks. "She published with us - but never under her own name. All her pieces ran as *Wren*. Her little joke; small bird, sharp eyes."
    He frowns, slower now. "Funny you'd ask, though. There *was* a story of hers, one term - accepted, set, sitting on the proofs page. And then she pulled it. Day before we went to print." The rag stops moving. "Only time she ever did that. Only time *anyone* asked me to. Never read it myself - proofs page was for the writers, I just set what came back. Always did wonder what was in it."
    - -(wendell_ask_about_story)
    * * [Ask why she pulled it] 
        "Didn't ask. She had the look of someone who'd already argued it out with herself and lost twice." He shrugs. "Her words, her call. That was the rule, and it was a good rule."
        -> wendell_ask_about_story
    * * [Ask if a copy survives]
        He shakes his head before you finish. "Gone. She pulled it, I cleared the proofs, the magazine site died when the school cut us. All gone now." He says it flat, certain, like reporting a death. "Paper we never printed and a website that doesn't exist. You can't find what was never made."
        -> wendell_ask_about_story
    * * [Ask about the proofs page]
        ~ knows_proofs_page = true
        "Web page, password the writers shared. Pieces went up for a final read before print. Newfangled at the time - I hated it, then I loved it. Saved a fortune in paper." A dry look. "Don't bother hunting for it. School server's been landfill for fifteen years."
        -> wendell_ask_about_story
    + + [Leave him to it]
        "Door's always open. Press is louder than the bell, so knock like you mean it."
        -> END
+ [Leave him to it]
"Door's always open. Press is louder than the bell, so knock like you mean it."
- -> END

=== linnea ===
{ found_story == false: 
    Linnea sits back on her heels when your shadow reaches her, trowel still in hand. Not unfriendly. Just unhurried, and clearly hoping you're lost rather than staying.
    "Help you?"
}
{ found_story && read_borrowed_light == false: She clocks something different in you before you speak — the look of someone who's been somewhere. "Help you?" A shade more guarded than usual. } 
{ read_borrowed_light: She looks up, and whatever's on your face makes her go still before the trowel's even down. She waits. She's good at waiting. } 

- (linnea_opener)
* [Ask about the garden.]
    "Council plot. Mine eleven years." She nods down the rows. "Beans sulk, garlic forgives. You learn who's worth the trouble." 
    -> linnea_opener
* { accepted_borrowed_light } [Ask about Cass.] 
    ~ talked_to_linnea = true
    Something settles in her face — not a frown, just a door easing shut. "We grew up together. Then we didn't." She turns a clod over. "He's well? Good. I'm glad." The *glad* is real. The subject is closed.
    -> linnea_opener
* { found_story } [Ask about the story she pulled.] 
    ~ talked_to_linnea = true
    A pause, exactly one beat too long. "People do talk in this town." She sets the trowel down, deliberate. "I wrote a lot of things at sixteen. I pulled one. That's allowed." Even, final. "Nothing worth digging up."
    -> linnea_opener
* { read_borrowed_light } [It's about Cass, isn't it?] 
    ~ voiced_recognition = true
    ~ talked_to_linnea = true
    She doesn't answer at first. You watch her arrive at it herself - that to know the story is about him you'd have had to read it, and to read it, it would have to still-
    "...Then it's still out there." Quiet. Not a question. The trowel goes into the soil and stays. "I took it down. I stood there and watched it go down." A breath. "Twenty years, and it just-"
    She doesn't finish. When she speaks again it's level, and she owns it without flinching. "I was sixteen, and I thought seeing through someone was the same as understanding them. It isn't. I was unkind to the kindest person I knew, and I was clever about it, which is worse."
    She brushes soil from her knees, suddenly somewhere else. "Does he still hum when he reads? He never knew he did it." A small breath that isn't quite a laugh. "He never knew."
    Leave it where it is." Gentle, but it's the closest she comes to asking for anything. "He went his whole life loved. Let him keep that. He doesn't need to meet the worst thing I ever wrote about him." She picks the trowel back up. "Whatever you do with it - and it's yours to do, you found it - do it knowing that's what I'd want."
    - - ( what_to_do)
    * * [Tell her you'll leave it buried]
        She nods, once, and looks back down at the soil — the conversation already returning to the ground where she's comfortable. "Thank you." A beat. "You didn't have to come and tell me any of it. Most people would've just... taken it to him." She doesn't look up. "Whatever you decide later — I'll not hold it against you. You're the only one who's seen all of it."
        -> END
    * * [Tell her Cass is the one looking for it.]
        ~ linnea_knows_cass_seeks = true
        The stillness comes back, deeper. "...Cass." She says his name like testing a sore tooth. "Of course it's Cass. He's trying to find his way back to me. With *that*." A long moment. "He doesn't even know what it is."
        She looks at you properly for the first time. "Then you're holding both ends of it, aren't you." Not cruel. Just true.
        -> what_to_do
    * * { linnea_knows_cass_seeks } [Hand back to Linnea]
        ~ borrowed_light_ending = "D"
        You could decide this. You're the only one who's read all of it - Cass's hope, Linnea's shame, the machine that doesn't forget. You could choose, and live with it.
        Instead you give it back to her. "He's looking because he wants you back," you tell her. "Not the story. You. The story's just the door he thought he could knock on. What happens next should be yours - not mine, and not a thing he found by accident. Yours."
        She's quiet a long time. Then she wipes her hands, slow, and stands - really stands, for the first time since you met her, like someone deciding to be somewhere. "Twenty years I've been certain that was the worst of me. Maybe it was. But he's two streets away, and you're telling me he's been trying to knock." A breath. "I'd rather answer the door than keep guarding it."
        She doesn't tell you what she'll do. That's the point - it's hers now. But she walks back to her beans lighter than she knelt in them.
        -> END
    * * [Say nothing / leave]
        You step back. She doesn't fill the silence — she's not the type. Just a glance up, level, that takes the measure of you and lets you go. "Mind the canes on your way."
        -> END
+ [Leave her to it.]
    "Mind the canes."
    -> END


=== journal
{ accepted_borrowed_light:
    Borrowed Light <> 
    { borrowed_light_ending != "": 
        (Completed)
        - else: (In progress)
    }
    Cass wants to find a story Linnea wrote at school. <>
    { knows_lead: Should start with the old magazine, maybe Kindling. Wendell at the Old Press might know. <> }
    { 
        - knows_about_story: 
        He doesn't know much about it. <>
        - else: 
        That's all I have to go on. <>
    } 
        He doesn't want her to hear about it. 
    { knows_wren: Linnea wrote as Wren in *Kindling* - and once pulled a story the day before printing. <> }
    { knows_proofs_page: Wendell never read it and swears nothing survives. It was on a proofs web page, though. Briefly. <>}
    { knows_proofs_page && knows_proofs_page_survived: Wendell was wrong — it's not all gone. The crawler kept *Kindling*. }
    { found_story && read_borrowed_light == false: "Found it. *Borrowed Light*, by Wren — a draft she pulled before it ever printed. It's sitting right there. I haven't opened it." }
    { found_story && read_borrowed_light: I read it. It's a portrait — a charming, hollow person everyone loves and no one knows. The laugh, the lean. }
    { found_story && read_borrowed_light == false && talked_to_linnea: "Spoke to Linnea. She pulled a story at sixteen and won't be drawn on it. She and Cass grew up together, then didn't." <> }
    { voiced_recognition: "Linnea knows it survived now - she worked it out the moment I knew it was about Cass. She owns what she wrote: unkind, clever, about the kindest person she knew. She'd rather it stayed buried. She asked if he still hums when he reads." <> } 
    { linnea_knows_cass_seeks: "She knows now that it's Cass doing the looking. She said I'm holding both ends of it." }
    { borrowed_light_ending == "A": "I showed Cass the story. He read it. He understood it - I watched him understand it. He thanked me, and folded himself back up, and I left." }
    { borrowed_light_ending == "B": "I told Cass everything first, then showed him. It hurt him, but it turned him toward her. He asked where she was." }
    { borrowed_light_ending == "C": "I told Cass it was gone. It isn't. He took it well. I'm the only one who knows, now." }
    { borrowed_light_ending == "D": "I gave the decision back to Linnea. She stood up. She didn't say what she'll do - it's hers." }
    { borrowed_light_ending == "E": "I gave Cass the dog story instead. He laughed - the real one. He got what he came for. The other story stays where it is." }
    -> END
}
Empty journal
-> END