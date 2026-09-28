import { LightningElement, api } from 'lwc';

const ICONS = {
    sunny: '☀️',
    partly: '⛅',
    cloudy: '☁️',
    rain: '🌧️',
    snow: '❄️',
    storm: '⛈️',
    fog: '🌫️',
    unknown: '🌡️'
};

export default class WeatherResult extends LightningElement {
    /** A GeoNamesWeatherService.WeatherData record, as returned by WeatherController. */
    @api weather;

    get icon() {
        return ICONS[this.weather?.iconKey] || ICONS.unknown;
    }
    get placeLabel() {
        const w = this.weather;
        return w.country ? `${w.locationName}, ${w.country}` : w.locationName;
    }
    get temperatureLabel() {
        const t = this.weather?.temperature;
        return t === null || t === undefined ? '—' : `${t} °C`;
    }
    get humidityLabel() {
        const h = this.weather?.humidity;
        return h === null || h === undefined ? '—' : `${h} %`;
    }
    get windLabel() {
        const w = this.weather?.windSpeedKmh;
        return w === null || w === undefined ? '—' : `${w} km/h`;
    }
    get stationLabel() {
        const w = this.weather;
        const when = w.observationTime ? ` · observed ${w.observationTime} UTC` : '';
        return `Station: ${w.stationName || 'n/a'}${when} · source: GeoNames`;
    }
}
