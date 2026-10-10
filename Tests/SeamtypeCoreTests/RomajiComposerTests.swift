import Testing
@testable import SeamtypeCore

@Suite struct RomajiComposerTests {
    @Test(arguments: [
        ("konnichiha", "こんにちは"), ("arigatou", "ありがとう"), ("kitte", "きって"), ("ra-men", "らーめん"),
        ("shinbun", "しんぶん"), ("kan'i", "かんい"), ("tenki", "てんき"), ("nihongo", "にほんご"),
        ("kyou", "きょう"), ("gakkou", "がっこう"), ("matcha", "まっちゃ"), ("shashin", "しゃしん"),
        ("tsukue", "つくえ"), ("fujisan", "ふじさん"), ("jouzu", "じょうず"), ("onna", "おんな"),
        ("konnnichiha", "こんにちは"), ("xtu", "っ"), ("dhisuku", "でぃすく"), ("wo", "を"),
        ("benkyou", "べんきょう"), ("hon", "ほん"), ("sushi", "すし"),
    ])
    func composes(romaji: String, expected: String) {
        let r = RomajiComposer.compose(romaji)
        #expect(r.text == expected)
        #expect(r.isClean)
    }

    @Test func pendingWhileTyping() {
        let r = RomajiComposer.compose("konnic", partial: true)
        #expect(r.text == "こんにc")
        #expect(r.pending == "c")
        #expect(r.strayLetters == 0)
        #expect(RomajiComposer.compose("hon", partial: true).text == "ほn")
    }

    @Test(arguments: ["strength", "dkssud", "world", "keyboard", "gksrmf"])
    func nonJapaneseLeavesStrayLetters(word: String) {
        #expect(RomajiComposer.compose(word).strayLetters > 0)
    }

    /// Like real Japanese IMEs, some English converts cleanly (hello → へっぉ);
    /// telling these apart is the detector's job, not the composer's.
    @Test func someEnglishConvertsCleanly() {
        #expect(RomajiComposer.compose("hello").text == "へっぉ")
    }

    @Test func katakana() {
        #expect(RomajiComposer.katakana("こんぴゅーたー") == "コンピューター")
    }
}
