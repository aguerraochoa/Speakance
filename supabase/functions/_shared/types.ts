export type ExpenseSource = "voice" | "text";

export type ParseExpenseRequest = {
  client_expense_id: string;
  source: ExpenseSource;
  captured_at_device: string;
  timezone?: string;
  audio_duration_seconds?: number;
  storage_bucket?: string;
  storage_object_path?: string;
  raw_text?: string;
  currency_hint?: string;
  allow_auto_save?: boolean;
  category_id?: string;
  trip_id?: string;
  trip_name?: string;
  payment_method_id?: string;
  payment_method_name?: string;
};

export type ParsedExpense = {
  amount: number;
  currency: string;
  category: string;
  description: string | null;
  merchant: string | null;
  expense_date: string; // YYYY-MM-DD
};

export type ParseExpenseResponse = {
  status: "saved" | "needs_review" | "rejected_limit" | "error";
  expense?: {
    id: string;
    client_expense_id: string;
    amount: number;
    currency: string;
    category: string;
    category_id?: string | null;
    description: string | null;
    merchant: string | null;
    expense_date: string;
    source: ExpenseSource;
    parse_status: "auto" | "edited" | "failed";
    trip_id?: string | null;
    trip_name?: string | null;
    payment_method_id?: string | null;
    payment_method_name?: string | null;
  };
  parse?: {
    confidence: number;
    raw_text: string;
    needs_review: boolean;
  };
  usage?: {
    daily_voice_used: number;
    daily_voice_limit: number;
  };
  error?: string;
};
