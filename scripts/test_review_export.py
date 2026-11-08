import copy
import unittest

import mark_reviewed as mr
import review_export as rx
import update_data as ud

TODAY = "2026-11-07"


def counter(**fields):
    base = {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "long, thin things", "jlpt": "N5",
            "sound": "h-b", "symbol": "pencil", "overrides": {}, "readings": {"1": ["いっぽん"]},
            "things": [{"id": "th1abc", "word": "傘", "kana": "かさ", "meaning": "umbrella", "fit": "primary"}],
            "examples": [{"id": "ex1abc", "jp": "傘を三本ください。", "en": "Three umbrellas, please."}],
            "pitfalls": [], "related": []}
    base.update(fields)
    return base


def docs():
    grammar_point = {
        "id": "n-desu", "title": "んです", "summary": "s", "jlpt": "N4",
        "usages": [{"id": "us1abc", "heading": "H", "explanation": "E",
                    "examples": [{"id": "ex2abc", "jp": "どうしたんですか。", "en": "What's wrong?"}]}],
        "pitfalls": [], "contrasts": [], "related": [],
    }
    verb = {"dict": "たべる", "kanji": "食べる", "type": "ru", "meaning": "to eat",
            "forms": {"te": "たべて", "potential": "たべられる"},
            "examples": [{"id": "ex3abc", "form": "te", "jp": "食べてから寝ます。", "en": "I eat, then sleep."}]}
    return {
        "verbs": {"verbs": [verb]},
        "words": {"words": [{"class": "noun", "dict": "いぬ", "kanji": "犬", "meaning": "dog"}]},
        "counters": {"counters": [counter()]},
        "grammar": {"grammar": [grammar_point]},
        "furigana": {"readings": {"傘": "かさ"}},
    }


def suggestion(id, action, dataset, kind, item_id, entry_id, item=None, **extra):
    s = {"id": id, "action": action, "dataset": dataset, "kind": kind, "item_id": item_id, "entry_id": entry_id,
         "parent_kind": None, "parent_id": None, "item_title": extra.pop("title", item_id), "item": item,
         "editable": None, "furigana": None, "comment": "", "credit": {"role": "native", "name": None},
         "decided_at": "2026-11-06T10:00:00Z"}
    s.update(extra)
    return s


def batch(suggestions=(), stamps=()):
    return {"files": {}, "suggestions": list(suggestions), "stamps": list(stamps)}


def stamp_request(id, dataset, entry, content_hash, by="native", name=None):
    return {"id": id, "dataset": dataset, "kind": "entry", "item_id": entry["id"], "entry_id": entry["id"],
            "item_title": entry.get("title", entry["id"]), "content_hash": content_hash, "by": by, "name": name,
            "reviewer_name": "Aiko", "created_at": "2026-11-06T10:00:00Z"}


class ChangeTests(unittest.TestCase):
    def test_change_sets_only_editable_keys(self):
        d = docs()
        verb = copy.deepcopy(d["verbs"]["verbs"][0])
        item = {**verb, "meaning": "to eat (a meal)", "forms": {"te": "WRONG"}}
        del item["kanji"]
        s = suggestion(1, "change", "verbs", "entry", "たべる", "たべる", item, editable=["meaning", "kanji"])
        report = rx.apply_batch(batch([s]), d, TODAY)
        out = d["verbs"]["verbs"][0]
        self.assertEqual(out["meaning"], "to eat (a meal)")
        self.assertNotIn("kanji", out)
        self.assertEqual(out["forms"], {"te": "たべて", "potential": "たべられる"})
        self.assertEqual(report.suggestion_ids, [1])
        self.assertEqual(len(report.applied), 1)

    def test_a_part_change_reaches_a_nested_example(self):
        d = docs()
        item = {"id": "ex2abc", "jp": "どうしたんですか。", "en": "What happened?"}
        s = suggestion(2, "change", "grammar", "example", "ex2abc", "n-desu", item, editable=["jp", "en"])
        rx.apply_batch(batch([s]), d, TODAY)
        self.assertEqual(d["grammar"]["grammar"][0]["usages"][0]["examples"][0]["en"], "What happened?")


class OverlapTests(unittest.TestCase):
    def usage_change(self, id, **edits):
        usage = docs()["grammar"]["grammar"][0]["usages"][0]
        item = {**usage, **edits}
        return suggestion(id, "change", "grammar", "usage", "us1abc", "n-desu", item,
                          editable=["heading", "explanation"])

    def test_two_changes_to_one_item_both_land(self):
        d = docs()
        report = rx.apply_batch(batch([self.usage_change(20, heading="New heading"),
                                       self.usage_change(21, explanation="New explanation")]), d, TODAY)
        usage = d["grammar"]["grammar"][0]["usages"][0]
        self.assertEqual((usage["heading"], usage["explanation"]), ("New heading", "New explanation"))
        self.assertEqual(report.suggestion_ids, [20, 21])

    def test_conflicting_changes_skip_the_later(self):
        d = docs()
        report = rx.apply_batch(batch([self.usage_change(22, heading="First"),
                                       self.usage_change(23, heading="Second")]), d, TODAY)
        self.assertEqual(d["grammar"]["grammar"][0]["usages"][0]["heading"], "First")
        self.assertEqual(report.suggestion_ids, [22])
        self.assertEqual(len(report.skipped), 1)
        self.assertIn("suggestion 23", report.skipped[0].text)
        self.assertIn("another change in this batch", report.skipped[0].text)

    def test_stale_change_is_skipped(self):
        d = docs()
        change = {**self.usage_change(24, heading="Late"), "stale": True}
        report = rx.apply_batch(batch([change]), d, TODAY)
        self.assertEqual(d["grammar"]["grammar"][0]["usages"][0]["heading"], "H")
        self.assertEqual(report.suggestion_ids, [])
        self.assertIn("the data changed since it was accepted", report.skipped[0].text)


class AdditionTests(unittest.TestCase):
    def test_addition_goes_to_its_parent(self):
        d = docs()
        example = {"id": "new123", "jp": "疲れたんです。", "en": "I'm tired."}
        under_usage = suggestion(3, "add", "grammar", "example", "new123", "n-desu", example,
                                 parent_kind="usage", parent_id="us1abc", furigana={"疲": "つか"})
        word = {"class": "noun", "dict": "ねこ", "kanji": "猫", "meaning": "cat"}
        new_word = suggestion(4, "add", "words", "entry", "noun:ねこ", "noun:ねこ", word)
        report = rx.apply_batch(batch([under_usage, new_word]), d, TODAY)
        self.assertEqual(d["grammar"]["grammar"][0]["usages"][0]["examples"][-1], example)
        self.assertEqual(d["words"]["words"][-1], word)
        self.assertEqual(d["furigana"]["readings"]["疲"], "つか")
        self.assertEqual(report.suggestion_ids, [3, 4])

    def test_furigana_added_once(self):
        d = docs()
        example = {"id": "new124", "jp": "傘です。", "en": "An umbrella."}
        s = suggestion(5, "add", "counters", "example", "new124", "hon", example,
                       parent_kind="entry", parent_id="hon", furigana={"傘": "がさ"})
        report = rx.apply_batch(batch([s]), d, TODAY)
        self.assertEqual(d["furigana"]["readings"]["傘"], "かさ")
        self.assertTrue(any("傘" in line.text for line in report.skipped))


class RemovalTests(unittest.TestCase):
    def test_change_and_removal_of_the_same_item(self):
        d = docs()
        item = {"id": "ex1abc", "jp": "傘を三本ください。", "en": "Changed."}
        change = suggestion(6, "change", "counters", "example", "ex1abc", "hon", item, editable=["jp", "en"])
        removal = suggestion(7, "delete", "counters", "example", "ex1abc", "hon")
        report = rx.apply_batch(batch([change, removal]), d, TODAY)
        self.assertEqual(d["counters"]["counters"][0]["examples"], [])
        self.assertEqual(report.suggestion_ids, [6, 7])
        later = suggestion(8, "change", "counters", "example", "ex1abc", "hon", item, editable=["en"])
        report = rx.apply_batch(batch([later]), d, TODAY)
        self.assertEqual([line.text for line in report.skipped], ["ex1abc (suggestion 8): no longer in the data"])
        self.assertEqual(report.suggestion_ids, [])

    def test_removing_an_entry(self):
        d = docs()
        report = rx.apply_batch(batch([suggestion(9, "delete", "words", "entry", "noun:いぬ", "noun:いぬ")]), d, TODAY)
        self.assertEqual(d["words"]["words"], [])
        self.assertEqual(report.suggestion_ids, [9])


class StampTests(unittest.TestCase):
    def test_stamp_written_with_name(self):
        d = docs()
        point = d["grammar"]["grammar"][0]
        req = stamp_request(1, "grammar", point, ud.review_hash(point), name="Aiko")
        report = rx.apply_batch(batch(stamps=[req]), d, TODAY)
        self.assertEqual(point["review"], {"by": "native", "on": TODAY, "sha256": ud.review_hash(point), "name": "Aiko"})
        self.assertEqual(ud.check_reviews(d["grammar"]["grammar"]), [])
        self.assertEqual(report.stamp_ids, [1])

    def test_stamp_skipped_when_the_batch_changes_its_entry(self):
        d = docs()
        entry = d["counters"]["counters"][0]
        req = stamp_request(2, "counters", entry, ud.review_hash(entry, ud.COUNTER_GENERATED))
        item = {**entry["examples"][0], "en": "Changed."}
        change = suggestion(10, "change", "counters", "example", "ex1abc", "hon", item, editable=["en"])
        report = rx.apply_batch(batch([change], [req]), d, TODAY)
        self.assertNotIn("review", entry)
        self.assertEqual(report.stamp_ids, [])
        self.assertTrue(any("hon" in line.text and "changes" in line.text for line in report.skipped))

    def test_stamp_skipped_when_the_entry_changed_since(self):
        d = docs()
        entry = d["counters"]["counters"][0]
        req = stamp_request(3, "counters", entry, "0" * 64)
        report = rx.apply_batch(batch(stamps=[req]), d, TODAY)
        self.assertNotIn("review", entry)
        self.assertEqual([line.text for line in report.skipped], ["hon (stamp 3): changed since it was stamped"])

    def test_change_removes_a_stale_stamp(self):
        d = docs()
        entry = d["counters"]["counters"][0]
        entry["review"] = mr.stamp(entry, "teacher", "2026-10-01", ud.COUNTER_GENERATED)
        item = {**entry, "meaning": "long things"}
        change = suggestion(11, "change", "counters", "entry", "hon", "hon", item, editable=["meaning"],
                            title="本 (ほん)")
        report = rx.apply_batch(batch([change]), d, TODAY)
        self.assertNotIn("review", entry)
        self.assertEqual([line.text for line in report.stamps_removed], ["本 (ほん): changed, needs a new review"])
        self.assertEqual(ud.check_reviews(d["counters"]["counters"], ud.COUNTER_GENERATED), [])


class SummaryTests(unittest.TestCase):
    def test_summary_has_no_email(self):
        d = docs()
        item = {"id": "ex1abc", "jp": "傘を三本ください。", "en": "Changed."}
        named = suggestion(12, "change", "counters", "example", "ex1abc", "hon", item, editable=["en"],
                           title="傘を三本ください。", credit={"role": "teacher", "name": "Sato"})
        anonymous = suggestion(13, "note", "words", "entry", "noun:いぬ", "noun:いぬ", title="いぬ (犬)",
                               comment="Check the kanji.")
        md = rx.summary_markdown(rx.apply_batch(batch([named, anonymous]), d, TODAY))
        self.assertNotIn("@", md)
        self.assertIn("傘を三本ください。", md)
        self.assertIn("Sato", md)
        self.assertIn("a native speaker", md)
        self.assertIn("Check the kanji.", md)
        self.assertIn("Site suggestion ids: 12, 13.", md)
        self.assertNotIn("#", md.replace("### ", "").replace("## ", ""))


if __name__ == "__main__":
    unittest.main()


def stamped_verb_docs():
    """docs() with a second example and a collocation on たべる, and stamps on the verb and both examples."""
    d = docs()
    verb = d["verbs"]["verbs"][0]
    verb["examples"].append({"id": "ex4abc", "form": "te", "jp": "食べて。", "en": "Eat."})
    verb["collocations"] = [{"id": "co1abc", "jp": "ご飯を食べる", "en": "eat a meal"}]
    verb["review"] = mr.stamp(verb, "teacher", "2026-11-01", ud.VERB_GENERATED)
    for example in verb["examples"]:
        example["review"] = mr.stamp(example, "teacher", "2026-11-01")
    return d


def part_stamp(id, dataset, kind, item, entry_id, generated=(), title=None):
    return {"id": id, "dataset": dataset, "kind": kind, "item_id": item.get("id") or entry_id, "entry_id": entry_id,
            "item_title": title or item.get("id") or entry_id, "content_hash": ud.review_hash(item, generated),
            "by": "native", "name": None, "reviewer_name": "Aiko", "created_at": "2026-11-06T10:00:00Z"}


class VerbWordExampleStampTests(unittest.TestCase):
    def test_writes_a_verb_stamp_and_an_example_stamp(self):
        d = docs()
        verb = d["verbs"]["verbs"][0]
        example = verb["examples"][0]
        report = rx.apply_batch(batch(stamps=[part_stamp(7, "verbs", "entry", verb, "たべる", ud.VERB_GENERATED),
                                              part_stamp(8, "verbs", "example", example, "たべる")]), d, TODAY)
        self.assertEqual(report.stamp_ids, [7, 8])
        self.assertEqual(ud.check_reviews([verb], ud.VERB_GENERATED, key=ud.verb_id), [])
        self.assertEqual(ud.check_reviews([example]), [])
        self.assertEqual(example["review"]["on"], TODAY)

    def test_writes_a_word_stamp(self):
        d = docs()
        word = d["words"]["words"][0]
        report = rx.apply_batch(batch(stamps=[part_stamp(9, "words", "entry", word, "noun:いぬ",
                                                         ud.WORD_GENERATED)]), d, TODAY)
        self.assertEqual(report.stamp_ids, [9])
        self.assertEqual(ud.check_reviews([word], ud.WORD_GENERATED, key=ud.word_id), [])

    def test_example_change_removes_only_its_stamp(self):
        d = stamped_verb_docs()
        verb = d["verbs"]["verbs"][0]
        a, b = verb["examples"]
        old_verb, old_b = dict(verb["review"]), dict(b["review"])
        request = part_stamp(10, "verbs", "example", a, "たべる")
        change = suggestion(3, "change", "verbs", "example", "ex3abc", "たべる",
                            {**{k: v for k, v in a.items() if k != "review"}, "en": "After eating, I sleep."},
                            editable=["jp", "en"], title="食べてから寝ます。")
        report = rx.apply_batch(batch([change], [request]), d, TODAY)
        self.assertNotIn("review", a)
        self.assertEqual([l.text for l in report.stamps_removed], ["食べてから寝ます。: changed, needs a new review"])
        self.assertTrue(any("this batch also changes it" in l.text for l in report.skipped))
        self.assertEqual(report.stamp_ids, [])
        self.assertEqual(verb["review"], old_verb)
        self.assertEqual(b["review"], old_b)

    def test_a_collocation_change_makes_the_verb_stamp_go(self):
        d = stamped_verb_docs()
        verb = d["verbs"]["verbs"][0]
        change = suggestion(4, "change", "verbs", "collocation", "co1abc", "たべる",
                            {"id": "co1abc", "jp": "ご飯を食べる", "en": "have a meal"}, editable=["en"])
        report = rx.apply_batch(batch([change]), d, TODAY)
        self.assertNotIn("review", verb)
        self.assertEqual(len(report.stamps_removed), 1)
        self.assertTrue(all("review" in ex for ex in verb["examples"]))

    def test_a_meaning_change_skips_a_requested_verb_stamp_but_not_an_example_stamp(self):
        d = docs()
        verb = d["verbs"]["verbs"][0]
        example = verb["examples"][0]
        stamps = [part_stamp(11, "verbs", "entry", verb, "たべる", ud.VERB_GENERATED),
                  part_stamp(12, "verbs", "example", example, "たべる")]
        change = suggestion(5, "change", "verbs", "entry", "たべる", "たべる",
                            {**verb, "meaning": "to eat (a meal)"}, editable=["meaning"])
        report = rx.apply_batch(batch([change], stamps), d, TODAY)
        self.assertEqual(report.stamp_ids, [12])
        self.assertNotIn("review", verb)
        self.assertEqual(ud.check_reviews([example]), [])

    def test_a_grammar_example_stamp_is_refused(self):
        d = docs()
        example = d["grammar"]["grammar"][0]["usages"][0]["examples"][0]
        report = rx.apply_batch(batch(stamps=[part_stamp(13, "grammar", "example", example, "n-desu")]), d, TODAY)
        self.assertEqual(report.stamp_ids, [])
        self.assertNotIn("review", example)
        self.assertTrue(any("can't be stamped" in l.text for l in report.skipped))
