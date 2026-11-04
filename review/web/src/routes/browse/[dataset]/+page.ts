import { error } from '@sveltejs/kit';
import { DATASETS, type Dataset } from '#lib/api.ts';
import type { EntryGenerator, PageLoad } from './$types';

// One prerendered page per dataset.
export const entries: EntryGenerator = () => DATASETS.map((dataset) => ({ dataset }));

export const load: PageLoad = ({ params }) => {
	if (!(DATASETS as readonly string[]).includes(params.dataset)) error(404, 'No such dataset');
	return { dataset: params.dataset as Dataset };
};
