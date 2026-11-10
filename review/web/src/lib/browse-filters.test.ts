import { expect, test } from 'vitest';
import { browseFilter } from './browse.ts';
import type { ItemSummary } from './api.ts';

const summary = (item_id: string, title: string, subtitle: string, jlpt: string | null): ItemSummary => ({
	item_id, title, subtitle, jlpt, parts: 0, approved: 0, open: 0, targets: 1
});

test('browseFilter keeps the level and search rules', () => {
	const items = [summary('a', '食べる', 'to eat', 'N5'), summary('b', '飲む', 'to drink', 'N5'), summary('c', '考える', 'to think', 'N4')];
	expect(browseFilter(items, '', 'N5').map((i) => i.item_id)).toEqual(['a', 'b']);
	expect(browseFilter(items, 'DRINK', '').map((i) => i.item_id)).toEqual(['b']);
	expect(browseFilter(items, '  食べ ', '').map((i) => i.item_id)).toEqual(['a']);
	expect(browseFilter(items, '', '')).toHaveLength(3);
});
