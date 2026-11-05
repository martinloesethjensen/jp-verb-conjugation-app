// Display names for datasets and data values.
import type { Dataset } from './api.ts';

export const DATASET_TITLES: Record<Dataset, string> = {
	verbs: 'Verbs',
	words: 'Words',
	counters: 'Counters',
	grammar: 'Grammar'
};

export const WORD_CLASSES: Record<string, string> = {
	'i-adjective': 'い-adjective',
	'na-adjective': 'な-adjective',
	noun: 'Noun'
};

export const FITS: Record<string, string> = {
	primary: 'Primary',
	casual: 'Casual',
	acceptable: 'Acceptable'
};
