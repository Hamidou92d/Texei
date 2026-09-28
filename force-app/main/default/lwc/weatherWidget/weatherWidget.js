import { LightningElement, api } from 'lwc';
import getWeatherByQuery from '@salesforce/apex/WeatherController.getWeatherByQuery';
import getWeatherByCoordinates from '@salesforce/apex/WeatherController.getWeatherByCoordinates';
import getWeatherForAccount from '@salesforce/apex/WeatherController.getWeatherForAccount';
import getWeatherForCurrentUser from '@salesforce/apex/WeatherController.getWeatherForCurrentUser';
import getLastReportSent from '@salesforce/apex/WeatherController.getLastReportSent';
import sendReport from '@salesforce/apex/WeatherController.sendReport';

/**
 * Orchestrator: owns Apex calls, geolocation, and record context (Home page vs.
 * Account record vs. public site). Delegates presentation to two children:
 *  - c-weather-search-bar  (input + buttons, emits "search" / "locate")
 *  - c-weather-result      (renders a WeatherData record via its "weather" @api property)
 */
export default class WeatherWidget extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api hideSendButton = false;
    @api disableGeolocation = false;

    weather;
    error;
    isLoading = false;
    isSending = false;
    sendMessage;
    sendMessageIsError = false;
    lastSent;

    connectedCallback() {
        this.refreshLastSent();
        if (this.isAccountContext) {
            this.run(() => getWeatherForAccount({ accountId: this.recordId }));
        } else {
            this.loadFromMyLocation();
        }
    }

    // Getters

    get isAccountContext() {
        return !!this.recordId && this.objectApiName === 'Account';
    }
    get isBusy() {
        return this.isLoading || this.isSending;
    }
    get canSend() {
        return !this.hideSendButton;
    }
    get sendDisabled() {
        return this.isBusy || !this.weather;
    }
    get sendButtonLabel() {
        return this.isAccountContext ? 'Send report to account contacts' : 'Send report to org users';
    }
    get showEmptyState() {
        return !this.isLoading && !this.weather && !this.error;
    }
    get sendMessageClass() {
        return `slds-var-m-top_x-small ${this.sendMessageIsError ? 'slds-text-color_error' : 'slds-text-color_success'}`;
    }
    get lastSentLabel() {
        return this.lastSent ? new Date(this.lastSent).toLocaleString() : null;
    }

    // Handlers (from children)

    handleSearch(event) {
        const query = event.detail.query;
        if (!query || !query.trim()) {
            this.error = 'Enter a city name or coordinates (lat, lng).';
            this.weather = undefined;
            return;
        }
        this.run(() => getWeatherByQuery({ query }));
    }

    handleUseMyLocation() {
        this.loadFromMyLocation();
    }

    async handleSend() {
        this.isSending = true;
        this.sendMessage = undefined;
        try {
            const result = await sendReport({
                recordId: this.isAccountContext ? this.recordId : null,
                latitude: this.weather.latitude,
                longitude: this.weather.longitude,
                locationLabel: this.weather.locationName
            });
            this.lastSent = result.sentAt;
            this.sendMessageIsError = false;
            this.sendMessage = `Report sent to ${result.recipientCount} ${result.audience}.`;
        } catch (e) {
            this.sendMessageIsError = true;
            this.sendMessage = this.reduceError(e);
        } finally {
            this.isSending = false;
        }
    }

    // Data loading

    async loadFromMyLocation() {
        this.startLoading();
        let coords;
        if (!this.disableGeolocation) {
            try {
                coords = await this.getBrowserPosition();
            } catch (e) {
                coords = undefined; // user denied geolocation, or unsupported, or timed out;
            }
        }
            
        try {
            if (coords) {
                this.weather = await getWeatherByCoordinates({
                    latitude: coords.latitude,
                    longitude: coords.longitude
                });
            } else {
                try {
                    this.weather = await getWeatherForCurrentUser();
                } catch (e) {
                    throw new Error(
                        'Your location is unavailable (geolocation blocked and no address on your profile). Enter a city or coordinates above.'
                    );
                }
            }
        } catch (e) {
            this.weather = undefined;
            this.error = this.reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }
    

    getBrowserPosition() {
        return new Promise((resolve, reject) => {
            if (!('geolocation' in navigator)) {
                reject(new Error('unsupported'));
                return;
            }
            navigator.geolocation.getCurrentPosition((p) => resolve(p.coords), reject, {
                timeout: 8000,
                maximumAge: 300000
            });
        });
    }

    async run(loader) {
        this.startLoading();
        try {
            this.weather = await loader();
        } catch (e) {
            this.weather = undefined;
            this.error = this.reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    startLoading() {
        this.isLoading = true;
        this.error = undefined;
        this.sendMessage = undefined;
    }

    async refreshLastSent() {
        if (this.hideSendButton) return;
        try {
            this.lastSent = await getLastReportSent({ recordId: this.isAccountContext ? this.recordId : null });
        } catch (e) {
            this.lastSent = undefined;
        }
    }

    reduceError(e) {
        return e?.body?.message || e?.message || 'Unexpected error.';
    }
}
