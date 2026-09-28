import { LightningElement, api } from 'lwc';

/**
 * A search bar component for weather information.
 * No Apex, no weather statement, no API calls are made in this component. It is a simple search bar that emits events when the user interacts with it.
 */
export default class WeatherSearchBar extends LightningElement {
    @api disabled = false;

    query = '';

    handleChange(event) {
        this.query = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearchClick();
        }
    }

    handleSearchClick() {
        this.dispatchEvent(new CustomEvent('search', { detail: { query: this.query } }));
    }

    handleLocateClick() {
        this.dispatchEvent(new CustomEvent('locate'));
    }
}
