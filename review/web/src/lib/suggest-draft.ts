/** What someone has typed into a suggest form so far, kept by the parent so it survives the form
 *  being rebuilt (the phone sheet and the inline form are separate instances). */
export type SuggestDraft = { values: Record<string, string>; answers: Record<string, string>; why: string };
