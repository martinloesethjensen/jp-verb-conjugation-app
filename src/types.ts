export type VerbType = "irr." | "ru" | "u";
export type TeGroup = "tte" | "nde" | "ite" | "ide" | "shite";
export type FormKey =
  | "masu_pos"
  | "masu_neg"
  | "masu_past"
  | "masu_past_neg"
  | "te"
  | "short_pos"
  | "short_neg"
  | "short_past"
  | "short_past_neg";

export interface VerbForms {
  masu_pos: string;
  masu_neg: string;
  masu_past: string;
  masu_past_neg: string;
  te: string;
  short_pos: string;
  short_neg: string;
  short_past: string;
  short_past_neg: string;
}

export interface VerbExample {
  form: FormKey;
  jp: string;
  en: string;
}

export interface Verb {
  type: VerbType;
  label: string;
  dict: string;
  kanji: string | null;
  meaning: string;
  description: string;
  notes?: string;
  teGroup?: TeGroup;
  forms: VerbForms;
  examples: VerbExample[];
}

export interface VerbData {
  version: string;
  description: string;
  verbs: Verb[];
}
