import json
from math import sin, pi


NAME = 'Sine Curve.json'


class Scenario:
    def __init__(self, glucose_values, basal_doses, bolus_doses, carb_entries):
        self.glucose_values = glucose_values
        self.basal_doses = basal_doses
        self.bolus_doses = bolus_doses
        self.carb_entries = carb_entries

    def json(self):
        return {
            'glucoseValues': [glucose.json() for glucose in self.glucose_values],
            'basalDoses': [basal.json() for basal in self.basal_doses],
            'bolusDoses': [bolus.json() for bolus in self.bolus_doses],
            'carbEntries': [entry.json() for entry in self.carb_entries]
        }


class GlucoseValue:
    def __init__(self, mgdl, date_offset):
        self.mgdl = mgdl
        self.date_offset = date_offset

    def json(self):
        return {
            'mgdlValue': self.mgdl,
            'dateOffset': self.date_offset
        }


class BasalDose:
    def __init__(self, units_per_hour, date_offset, duration):
        self.units_per_hour = units_per_hour
        self.date_offset = date_offset
        self.duration = duration

    def json(self):
        return {
            'unitsPerHourValue': self.units_per_hour,
            'dateOffset': self.date_offset,
            'duration': self.duration
        }


class BolusDose:
    def __init__(self, units, date_offset, delivery_duration):
        self.units = units
        self.date_offset = date_offset
        self.delivery_duration = delivery_duration

    def json(self):
        return {
            'unitsValue': self.units,
            'dateOffset': self.date_offset,
            'deliveryDuration': self.delivery_duration
        }


class CarbEntry:
    def __init__(self, grams, date_offset,
                 absorption_time, entered_at_offset=None):
        self.grams = grams
        self.date_offset = date_offset
        self.absorption_time = absorption_time
        self.entered_at_offset = entered_at_offset

    def json(self):
        d = {
            'gramValue': self.grams,
            'dateOffset': self.date_offset,
            'absorptionTime': self.absorption_time
        }

        if self.entered_at_offset is not None:
            d['enteredAtOffset'] = self.entered_at_offset

        return d


def minutes(count):
    return 60 * count


def hours(count):
    return 60 * minutes(count)


def make_scenario():
    return Scenario(
        make_glucose_values(),
        make_basal_doses(),
        make_bolus_doses(),
        make_carb_entries()
    )


def make_glucose_values():
    amplitude = 40
    base = 110
    period = hours(3)
    offsets = [minutes(t * 5) for t in range(-120, 120)]
    values = [base + amplitude * sin(2 * pi / period * t) for t in offsets]
    return [GlucoseValue(value, offset) for value, offset in zip(values, offsets)]


def make_basal_doses():
    return [
        BasalDose(1.2, hours(-1.5), hours(0.5)),
        BasalDose(0.9, hours(-1.0), hours(0.5)),
        BasalDose(0.8, hours(-0.5), hours(0.5))
    ]


def make_bolus_doses():
    return [
        BolusDose(3.0, minutes(-15), minutes(2)),
    ]


def make_carb_entries():
    return [
        CarbEntry(30, minutes(-5), hours(3)),
        CarbEntry(15, minutes(15), hours(2), entered_at_offset=minutes(-15)),
    ]


if __name__ == '__main__':
    with open(NAME, 'w') as outfile:
        json.dump(make_scenario().json(), outfile)
