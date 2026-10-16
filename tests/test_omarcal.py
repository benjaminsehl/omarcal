# Run: python3 -m unittest discover -s tests
import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("omarcal", os.path.join(HERE, "..", "bin", "omarcal"))
spec = importlib.util.spec_from_loader("omarcal", loader)
omarcal = importlib.util.module_from_spec(spec)
loader.exec_module(omarcal)


class Links(unittest.TestCase):
    def test_conference_entry_point_wins(self):
        ev = {
            "hangoutLink": "https://meet.google.com/aaa-bbbb-ccc",
            "conferenceData": {
                "entryPoints": [
                    {"entryPointType": "phone", "uri": "tel:+1-555"},
                    {"entryPointType": "video", "uri": "https://us02web.zoom.us/j/123?pwd=x"},
                ],
                "conferenceSolution": {"name": "Zoom Meeting"},
            },
        }
        self.assertEqual(omarcal.conference(ev), ("https://us02web.zoom.us/j/123?pwd=x", "zoom", "Zoom Meeting"))

    def test_hangout_link(self):
        ev = {"hangoutLink": "https://meet.google.com/aaa-bbbb-ccc"}
        self.assertEqual(omarcal.conference(ev)[1], "meet")

    def test_location_then_description(self):
        ev = {"location": "Room 4", "description": 'Join: <a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y">here</a>'}
        url, key, name = omarcal.conference(ev)
        self.assertEqual(key, "teams")
        self.assertTrue(url.startswith("https://teams.microsoft.com/l/meetup-join/"))
        self.assertNotIn('"', url)

    def test_html_entities_and_trailing_punctuation(self):
        url, key, _ = omarcal.find_link("Call: https://zoom.us/j/99?pwd=a&amp;b=c.")
        self.assertEqual((url, key), ("https://zoom.us/j/99?pwd=a&b=c", "zoom"))

    def test_no_link(self):
        self.assertEqual(omarcal.conference({"location": "Café Eins"}), ("", "", ""))


class Normalize(unittest.TestCase):
    CAL = {"id": "me@x.com", "summary": "me@x.com", "backgroundColor": "#7fb2ac", "primary": True}

    def test_timed(self):
        ev = omarcal.normalize({
            "id": "1", "summary": "Standup",
            "start": {"dateTime": "2026-10-16T10:00:00Z"}, "end": {"dateTime": "2026-10-16T10:15:00Z"},
            "attendees": [{"self": True, "responseStatus": "tentative"}, {"email": "a"}, {"email": "room", "resource": True}],
            "hangoutLink": "https://meet.google.com/aaa-bbbb-ccc",
            "location": "https://meet.google.com/aaa-bbbb-ccc",
        }, self.CAL)
        self.assertEqual(ev["end"] - ev["start"], 15 * 60000)
        self.assertEqual(ev["response"], "tentative")
        self.assertEqual(ev["guests"], 1)
        self.assertEqual(ev["location"], "")  # the link isn't a place
        self.assertFalse(ev["allDay"])

    def test_all_day_and_defaults(self):
        ev = omarcal.normalize({"id": "2", "start": {"date": "2026-10-16"}, "end": {"date": "2026-10-17"}}, self.CAL)
        self.assertTrue(ev["allDay"])
        self.assertEqual(ev["title"], "(No title)")
        self.assertEqual(ev["response"], "accepted")
        self.assertEqual(ev["end"] - ev["start"], 24 * 3600000)


class Disabled(unittest.TestCase):
    def test_service_disabled(self):
        payload = {"error": {"code": 403, "message": "Google Calendar API has not been used in project 1 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=1 then retry.",
                             "errors": [{"reason": "accessNotConfigured"}],
                             "details": [{"reason": "SERVICE_DISABLED", "metadata": {"activationUrl": "https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=1"}}]}}
        self.assertEqual(omarcal.api_disabled(payload), "https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=1")

    def test_url_from_message(self):
        payload = {"error": {"message": "Enable it by visiting https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=2 then retry.",
                             "errors": [{"reason": "accessNotConfigured"}]}}
        self.assertTrue(omarcal.api_disabled(payload).endswith("project=2"))

    def test_other_errors(self):
        self.assertIsNone(omarcal.api_disabled({"error": {"errors": [{"reason": "rateLimitExceeded"}]}}))
        self.assertIsNone(omarcal.api_disabled({}))


class Args(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(omarcal.parse_args(["--days", "3", "--cached", "--title=Hi there"]),
                         {"days": "3", "cached": True, "title": "Hi there"})


if __name__ == "__main__":
    unittest.main()
