# Captured game data from the nightly capture of 8 Oct 2026 (about 04:22 UTC), for testing the cash forecast.
# Balances, the last day's flight income and costs, flights a day, and every payment the game listed ahead.
# Payment codes: a = A321NEO Light, n = A320NEO Light, x = A321XLR, u = A350-900ULR, e = Embraer 195 E2,
# w = week-end closing. Times are as the game's events page shows them, at the airline's home airport.
import json, sys

TYPES = {"a": "Airbus A321NEO Light", "n": "Airbus A320NEO Light", "x": "Airbus A321XLR", "u": "Airbus A350-900ULR", "e": "Embraer 195 E2"}
HOME = {"Pan American": "JFK", "Kingfisher": "DEL", "Ryanair": "CDG", "Virgin Atlantic": "LGW", "China Eastern": "PVG", "Malaysia Airlines": "KUL"}
UTC = {"CDG": 1, "DEL": 5.5, "JFK": -5, "KUL": 8, "LGW": 0, "PVG": 8}
BAL = {  # cash, captured at
    "China Eastern": (6012763, "2026-10-08T04:22:36Z"), "Kingfisher": (6778774, "2026-10-08T04:21:44Z"),
    "Malaysia Airlines": (5443067, "2026-10-08T04:22:48Z"), "Pan American": (6841343, "2026-10-08T04:22:11Z"),
    "Ryanair": (9713920, "2026-10-08T04:22:00Z"), "Virgin Atlantic": (4757844, "2026-10-08T04:22:24Z")}
OPS = {  # flights, income, costs over the last day's bank statement
    "Virgin Atlantic": (82, 2124463, 1606789), "Malaysia Airlines": (60, 2161116, 815944), "Pan American": (56, 2611315, 1003764),
    "Kingfisher": (48, 2023270, 809715), "China Eastern": (78, 2317093, 1017901), "Ryanair": (144, 2925250, 1169409)}
FPD = {"Ryanair": 144, "Kingfisher": 47.714, "Pan American": 56, "China Eastern": 78, "Virgin Atlantic": 82, "Malaysia Airlines": 60}
CLOSING = {"China Eastern": "China Eastern Airlines", "Kingfisher": "Kingfisher Airlines", "Ryanair": "Ryanair",
           "Pan American": "Pan American World Airways", "Virgin Atlantic": "Virgin Atlantic", "Malaysia Airlines": "Malaysia Airlines"}
A, E = 235648, 177135
PAY = {
    "China Eastern": [("08", "07:55", A, "a"), ("09", "13:25", 599775, "w"), ("09", "04:55", A, "a"), ("10", "01:55", A, "a"), ("10", "03:53", E, "e"),
        ("10", "22:55", A, "a"), ("11", "19:55", A, "a"), ("11", "19:57", A, "a"), ("12", "16:55", A, "a"), ("12", "16:57", A, "a"),
        ("13", "13:55", A, "a"), ("13", "13:57", A, "a"), ("13", "19:47", E, "e"), ("14", "10:47", E, "e"), ("14", "10:55", A, "a"),
        ("14", "10:57", A, "a"), ("15", "07:55", A, "a"), ("15", "07:57", A, "a"), ("16", "04:55", A, "a"), ("17", "01:55", A, "a")],
    "Kingfisher": [("08", "07:35", 237570, "a"), ("08", "07:37", 286245, "x"), ("08", "16:35", 719395, "u"), ("09", "04:37", 286245, "x"),
        ("09", "09:04", 647459, "w"), ("10", "01:37", 286245, "x"), ("10", "07:15", 214510, "n"), ("10", "22:37", 237570, "a"),
        ("11", "19:37", 237570, "a"), ("12", "16:37", 237570, "a"), ("13", "13:37", 237570, "a"), ("14", "10:37", 719395, "u"),
        ("14", "10:37", 237570, "a"), ("15", "07:37", 237570, "a"), ("15", "07:39", 286245, "x")],
    "Ryanair": [("08", "12:29", 174734, "e"), ("08", "16:21", 1182988, "w"), ("09", "00:29", 237143, "a"), ("09", "03:29", 174734, "e"),
        ("09", "18:29", 174734, "e"), ("09", "21:29", 237143, "a"), ("10", "01:40", 240185, "a"), ("10", "09:29", 174734, "e"),
        ("10", "18:29", 237143, "a"), ("11", "00:29", 174734, "e"), ("11", "15:29", 237143, "a"), ("11", "15:29", 174734, "e"),
        ("12", "06:29", 174734, "e"), ("12", "12:29", 237143, "a"), ("12", "15:02", E, "e"), ("12", "21:29", 174734, "e"),
        ("13", "09:29", 237143, "a"), ("13", "12:29", E, "e"), ("14", "03:29", E, "e"), ("14", "06:29", 237143, "a"),
        ("14", "21:31", 174734, "e"), ("15", "03:31", 237143, "a")],
    "Pan American": [("08", "22:36", 789558, "w"), ("10", "22:03", 240185, "a"), ("11", "15:11", 240185, "a"), ("11", "18:51", 240185, "a"),
        ("11", "19:33", 286245, "x"), ("11", "19:53", 286245, "x"), ("11", "19:53", 286245, "x"), ("12", "13:55", 240185, "a"),
        ("12", "16:01", 286245, "x"), ("13", "10:55", 240185, "a"), ("13", "21:33", 719395, "u")] + [("13", "22:05", 283383, "x")] * 5,
    "Virgin Atlantic": [("08", "04:44", 560559, "w"), ("08", "20:53", A, "a"), ("09", "17:53", A, "a"), ("09", "19:52", E, "e"),
        ("10", "14:53", A, "a"), ("11", "11:53", A, "a"), ("11", "11:55", A, "a"), ("12", "08:53", A, "a"), ("12", "08:55", A, "a"),
        ("13", "05:53", A, "a"), ("13", "05:55", A, "a"), ("13", "11:47", E, "e"), ("14", "02:47", E, "e"), ("14", "02:53", A, "a"),
        ("14", "02:55", A, "a"), ("14", "23:53", A, "a"), ("14", "23:55", A, "a"), ("15", "20:53", A, "a"), ("16", "17:53", A, "a"),
        ("15", "04:44", 713758, "w")],
    "Malaysia Airlines": [("09", "04:54", A, "a"), ("09", "13:30", 554048, "w"), ("10", "01:54", A, "a"), ("10", "03:53", E, "e"),
        ("10", "22:54", A, "a"), ("11", "19:54", A, "a"), ("11", "19:55", A, "a"), ("12", "16:54", A, "a"), ("12", "16:55", A, "a"),
        ("13", "13:54", A, "a"), ("13", "13:55", A, "a"), ("13", "19:47", E, "e"), ("14", "10:47", E, "e"), ("14", "10:54", A, "a"),
        ("14", "10:55", A, "a"), ("15", "07:54", A, "a"), ("15", "07:55", A, "a"), ("16", "04:54", A, "a"), ("17", "01:54", A, "a")]}
TYPES_REF = [{"name": "E195-E2", "priceM": 1.8}, {"name": "A321 NEO LIGHT", "priceM": 2.4}, {"name": "A321XLR", "priceM": 2.8},
             {"name": "A350-900ULR", "priceM": 7.1}, {"name": "A320NEO LIGHT", "priceM": 2.15}]
CONFIGS = [{"code": c, "costM": m} for c, m in [("E195-STD", 0.062), ("321-LEI OLD", 0.1956), ("321-LP", 0.2064), ("321-STD", 0.108),
           ("XLR-LP", 0.2064), ("XLR-CMF", 0.2114), ("350-CMF", 0.43128), ("E195-LEI", 0.097), ("320-LEI", 0.1626), ("321-LEI", 0.192)]]


def data():
    events = [{"airline": al, "event_date": "2026-10-" + d, "event_time": t, "debit": m,
               "descr": f"Week-end closing of {CLOSING[al]}" if k == "w" else f"Leasing payment for X ({TYPES[k]})"}
              for al, rows in PAY.items() for d, t, m, k in rows]
    return {"bal": [{"airline": al, "amount": v, "captured_at": at} for al, (v, at) in BAL.items()],
            "ops": {al: {"airline": al, "flights": f, "income": i, "costs": c} for al, (f, i, c) in OPS.items()},
            "events": events, "fpd": FPD, "home": HOME, "utc": UTC, "types": TYPES_REF, "configs": CONFIGS}


if __name__ == "__main__":
    json.dump(data(), sys.stdout)
