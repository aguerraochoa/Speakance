import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  ParseExpenseRequest,
  ParseExpenseResponse,
  ParsedExpense,
} from "../_shared/types.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_VOICE_SECONDS = 15;
const DEFAULT_DAILY_VOICE_LIMIT = 50;
const AUTO_SAVE_CONFIDENCE_THRESHOLD = 0.9;
const OPENAI_MODEL = "gpt-4o-mini";
const OPENAI_TRANSCRIBE_MODEL = "whisper-1";
const VOICE_CAPTURES_BUCKET = "voice-captures";

const DEFAULT_CATEGORY_NAMES = [
  "Food",
  "Groceries",
  "Transport",
  "Entertainment",
  "Shopping",
  "Utilities",
  "Subscriptions",
  "Other",
] as const;

const CATEGORY_SET = new Set<string>(DEFAULT_CATEGORY_NAMES);

const DEFAULT_CATEGORY_KEYWORDS: Record<string, string[]> = {
  Food: [
    "food", "meal", "meals", "breakfast", "lunch", "dinner", "brunch",
    "snack", "snacks", "restaurant", "restaurante", "cafe", "cafeteria", "bakery",
    "coffee", "latte", "espresso", "tea", "juice", "smoothie", "water",
    "soda", "drink", "drinks", "beer", "wine", "pizza", "burger",
    "burgers", "taco", "tacos", "burrito", "sushi", "ramen", "noodles",
    "sandwich", "sandwiches", "salad", "bbq", "steak", "chicken",
    "dessert", "icecream", "donut", "donuts", "pastry", "cookies",
    "delivery", "takeout", "doordash", "ubereats", "rappi", "grubhub",
    "instacart", "didi",
  ],
  Groceries: [
    "groceries", "grocery", "supermarket", "market", "produce",
    "costco", "walmart", "wholefoods", "whole foods", "traderjoes",
    "trader joe", "safeway", "kroger", "aldi", "instacart",
  ],
  Transport: [
    "transport", "transportation", "commute", "commuting", "uber", "lyft",
    "taxi", "cab", "rideshare", "bus", "metro", "subway", "train",
    "tram", "rail", "ferry", "flight", "airfare", "airport", "ticket",
    "tickets", "parking", "toll", "tolls", "gas", "fuel", "diesel",
    "petrol", "ev", "charging", "transit", "bike", "bicycle", "scooter",
    "moped", "uberx", "uberxl", "bolt", "ola", "didi",
  ],
  Entertainment: [
    "entertainment", "fun", "movie", "movies", "cinema", "theater",
    "theatre", "netflix", "spotify", "hulu", "disney", "streaming",
    "youtube", "primevideo", "gaming", "game", "games", "steam", "xbox",
    "playstation", "nintendo", "concert", "festival", "show", "shows",
    "club", "bar", "bars", "karaoke", "bowling", "arcade", "museum",
    "event", "events", "party", "cocktail", "cocktails", "drinks",
    "beer", "wine",
  ],
  Shopping: [
    "shopping", "shop", "store", "amazon", "mall", "target", "walmart",
    "costco", "ikea", "purchase", "purchases", "bought", "buy", "clothes",
    "clothing", "shirt", "shirts", "pants", "jeans", "jacket", "hoodie",
    "shoes", "sneakers", "boots", "bag", "bags", "backpack", "makeup",
    "cosmetics", "skincare", "sephora", "electronics", "headphones",
    "phonecase", "case", "keyboard", "mouse", "monitor", "furniture",
    "decor", "homegoods", "appliance", "appliances", "book", "books",
    "notebook", "supplies", "gift", "gifts",
  ],
  Utilities: [
    "bill", "bills", "rent", "mortgage", "lease", "utilities", "utility",
    "electric", "electricity", "power", "water", "sewer", "internet",
    "wifi", "phone", "cell", "mobile", "telecom", "insurance", "premium",
    "premiums", "loan", "loans", "credit", "debt", "payment", "payments",
    "icloud", "hosting", "domain", "server", "tax", "taxes", "hoa", "maintenance",
    "repair", "repairs", "tuition", "school", "daycare", "childcare",
    "medical", "doctor", "hospital", "pharmacy", "medicine",
  ],
  Subscriptions: [
    "subscription", "subscriptions", "monthly", "membership", "memberships",
    "netflix", "spotify", "applemusic", "apple music", "youtube premium",
    "disney", "hulu", "primevideo", "prime video", "icloud", "chatgpt",
    "notion", "canva", "adobe", "software", "license", "licence",
  ],
  Other: [
    "other", "misc", "miscellaneous", "unknown", "random", "cash",
    "transfer", "fee", "fees", "tip", "tips", "donation", "charity",
    "giftcard", "adjustment", "correction", "refund",
  ],
};

const CATEGORY_ALIASES: Record<string, string> = Object.fromEntries(
  Object.entries(DEFAULT_CATEGORY_KEYWORDS).flatMap(([category, keywords]) =>
    keywords.map((keyword) => [keyword.toLowerCase(), category])
  ),
) as Record<string, string>;

type ProfileRow = {
  daily_voice_limit: number | null;
  timezone: string | null;
  default_currency: string | null;
};

type CategoryRow = {
  id: string;
  name: string;
  is_default: boolean;
};

type CategoryHintRow = {
  category_id: string;
  phrase: string;
};

type PaymentMethodRow = {
  id: string;
  name: string;
  network: string | null;
  is_active: boolean;
};

type PaymentMethodAliasRow = {
  payment_method_id: string;
  phrase: string;
};

type ParserCategoryContext = {
  categories: { id: string; name: string }[];
  categoryNames: Set<string>;
  aliasToCategory: Record<string, string>;
  explicitCategoryTokens: Set<string>;
  categoryIDsByName: Map<string, string>;
  hintsByCategoryName: Record<string, string[]>;
};

type ParserPaymentMethodContext = {
  methodsById: Map<string, { id: string; name: string }>;
  aliasToMethodIDs: Map<string, string[]>;
};

type DeterministicParse = {
  parsed: ParsedExpense;
  confidence: number;
  metadata: {
    hasAmount: boolean;
    hasExplicitCurrency: boolean;
    usedDefaultCurrency: boolean;
    hasExplicitCategory: boolean;
    tokenCount: number;
  };
};

type ParseOutcome = {
  parsed: ParsedExpense;
  confidence: number;
  provider: string;
  model: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAiApiKey = Deno.env.get("OPENAI_API_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      return json(
        { status: "error", error: "Missing Supabase env vars" } satisfies ParseExpenseResponse,
        500,
      );
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const bearerToken = authHeader.replace(/^Bearer\s+/i, "").trim();
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);
    if (!bearerToken) {
      return json(
        { status: "error", error: "Unauthorized" } satisfies ParseExpenseResponse,
        401,
      );
    }

    const { data: authData, error: authError } = await adminClient.auth.getUser(bearerToken);
    if (authError || !authData.user) {
      return json(
        { status: "error", error: authError?.message || "Unauthorized" } satisfies ParseExpenseResponse,
        401,
      );
    }
    const user = authData.user;

    const body = (await req.json()) as ParseExpenseRequest;
    const validationError = validateRequest(body);
    if (validationError) {
      return json(
        { status: "error", error: validationError } satisfies ParseExpenseResponse,
        400,
      );
    }

    const profile = await getProfile(adminClient, user.id);
    const [parserCategoryContext, parserPaymentMethodContext] = await Promise.all([
      loadParserCategoryContext(adminClient, user.id),
      loadPaymentMethodContext(adminClient, user.id),
    ]);
    const dailyVoiceLimit = profile?.daily_voice_limit ?? DEFAULT_DAILY_VOICE_LIMIT;
    const tz = body.timezone ?? profile?.timezone ?? "UTC";

    const dailyVoiceUsed = await countDailyVoiceUsage(
      adminClient,
      user.id,
      body.captured_at_device,
      tz,
    );
    if (body.source === "voice" && dailyVoiceUsed >= dailyVoiceLimit) {
      return json(
        {
          status: "rejected_limit",
          usage: { daily_voice_used: dailyVoiceUsed, daily_voice_limit: dailyVoiceLimit },
          error: "Daily voice limit reached",
        } satisfies ParseExpenseResponse,
        429,
      );
    }

    const inputResolution = await resolveInputText({
      body,
      adminClient,
      openAiApiKey,
    });
    const rawText = inputResolution.text;
    if (!rawText) {
      const isVoicePlaceholder = isVoicePlaceholderText(body.raw_text ?? "");
      return json(
        {
          status: "error",
          error: body.source === "voice"
            ? (inputResolution.error
              ?? (isVoicePlaceholder
                ? "Voice transcription failed. Try holding longer and speaking clearly, or switch to Text."
                : "Could not resolve transcript text from request"))
            : "Could not resolve transcript text from request",
        } satisfies ParseExpenseResponse,
        400,
      );
    }

    const aiOutcome = await parseExpenseWithOpenAI({
      apiKey: openAiApiKey,
      rawText,
      capturedAtDevice: body.captured_at_device,
      currencyHint: body.currency_hint,
      languageHint: body.language_hint,
      defaultCurrency: profile?.default_currency ?? undefined,
      categoryContext: parserCategoryContext,
    });

    let outcome: ParseOutcome;
    if (aiOutcome) {
      outcome = aiOutcome;
    } else {
      const deterministic = parseExpenseDeterministically(rawText, {
        currencyHint: body.currency_hint,
        defaultCurrency: profile?.default_currency ?? undefined,
        capturedAtDevice: body.captured_at_device,
        categoryContext: parserCategoryContext,
      });
      outcome = {
        parsed: deterministic.parsed,
        confidence: deterministic.confidence,
        provider: "deterministic",
        model: "rules-v1",
      };
    }

    const needsReview = outcome.confidence < AUTO_SAVE_CONFIDENCE_THRESHOLD || body.allow_auto_save === false;

    const parsedCategoryId = resolveCategoryIDForParsedCategory(outcome.parsed.category, parserCategoryContext);
    const categoryRef = await validateCategoryRef(adminClient, user.id, body.category_id);
    const finalCategoryId = categoryRef?.id ?? parsedCategoryId;
    const finalCategoryName = categoryRef?.name ?? outcome.parsed.category;
    const tripRef = await validateOwnedRef(adminClient, "trips", user.id, body.trip_id);
    const detectedPaymentMethod = detectPaymentMethodReference(rawText, parserPaymentMethodContext);
    const paymentMethodRef = await validateOwnedRef(
      adminClient,
      "payment_methods",
      user.id,
      body.payment_method_id ?? detectedPaymentMethod?.id,
    );
    const finalPaymentMethodName = paymentMethodRef
      ? (body.payment_method_name ?? detectedPaymentMethod?.name ?? null)
      : null;

    const { data: savedExpense, error: upsertError } = await adminClient
      .from("expenses")
      .upsert(
        {
          user_id: user.id,
          client_expense_id: body.client_expense_id,
          amount: outcome.parsed.amount,
          currency: outcome.parsed.currency,
          category: finalCategoryName,
          category_id: finalCategoryId,
          description: outcome.parsed.description,
          merchant: outcome.parsed.merchant,
          trip_id: tripRef,
          trip_name: body.trip_name ?? null,
          payment_method_id: paymentMethodRef,
          payment_method_name: finalPaymentMethodName,
          expense_date: outcome.parsed.expense_date,
          captured_at_device: body.captured_at_device,
          synced_at: new Date().toISOString(),
          source: body.source,
          parse_status: "auto",
          parse_confidence: outcome.confidence,
          raw_text: rawText,
          audio_duration_seconds: body.audio_duration_seconds ?? null,
        },
        { onConflict: "user_id,client_expense_id" },
      )
      .select("id, client_expense_id, amount, currency, category, category_id, description, merchant, expense_date, source, parse_status, trip_id, trip_name, payment_method_id, payment_method_name")
      .single();

    if (upsertError || !savedExpense) {
      return json(
        { status: "error", error: upsertError?.message ?? "Failed to save expense" } satisfies ParseExpenseResponse,
        500,
      );
    }

    await adminClient.from("ai_usage_events").insert({
      user_id: user.id,
      client_expense_id: body.client_expense_id,
      event_type: body.source === "voice" ? "voice_parse" : "text_parse",
      provider: outcome.provider,
      model: outcome.model,
      audio_seconds: body.audio_duration_seconds ?? null,
      estimated_cost_usd: outcome.provider === "openai" ? null : 0,
    });

    await deleteUploadedVoiceCaptureIfPresent(adminClient, body);

    const response: ParseExpenseResponse = {
      status: needsReview ? "needs_review" : "saved",
      expense: savedExpense,
      parse: {
        confidence: outcome.confidence,
        raw_text: rawText,
        needs_review: needsReview,
      },
      usage: {
        daily_voice_used: body.source === "voice" ? dailyVoiceUsed + 1 : dailyVoiceUsed,
        daily_voice_limit: dailyVoiceLimit,
      },
    };

    return json(response, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ status: "error", error: message } satisfies ParseExpenseResponse, 500);
  }
});

async function resolveInputText(opts: {
  body: ParseExpenseRequest;
  adminClient: ReturnType<typeof createClient>;
  openAiApiKey: string | undefined;
}): Promise<{ text: string | null; error: string | null }> {
  const rawTextCandidate = opts.body.raw_text?.trim();
  const rawText = rawTextCandidate && !isVoicePlaceholderText(rawTextCandidate) ? rawTextCandidate : null;
  if (opts.body.source !== "voice") {
    return { text: rawText ?? null, error: null };
  }

  const storageObjectPath = opts.body.storage_object_path?.trim();
  if (storageObjectPath) {
    const transcribed = await transcribeVoiceCaptureFromStorage({
      adminClient: opts.adminClient,
      openAiApiKey: opts.openAiApiKey,
      bucket: (opts.body.storage_bucket?.trim() || VOICE_CAPTURES_BUCKET),
      objectPath: storageObjectPath,
      languageHint: normalizeLanguageHint(opts.body.language_hint),
    });
    if (transcribed.text) return { text: transcribed.text, error: null };
    if (transcribed.error) return { text: null, error: transcribed.error };
  }

  return { text: rawText ?? null, error: null };
}

async function transcribeVoiceCaptureFromStorage(opts: {
  adminClient: ReturnType<typeof createClient>;
  openAiApiKey: string | undefined;
  bucket: string;
  objectPath: string;
  languageHint?: "en" | "es";
}): Promise<{ text: string | null; error: string | null }> {
  if (!opts.openAiApiKey) {
    console.error("OPENAI_API_KEY missing; cannot transcribe voice capture");
    return { text: null, error: "Voice transcription unavailable (server missing OPENAI_API_KEY)." };
  }

  const { data, error } = await opts.adminClient.storage
    .from(opts.bucket)
    .download(opts.objectPath);

  if (error || !data) {
    console.error("Failed to download voice capture from storage", error?.message);
    return { text: null, error: "Voice upload could not be read from storage. Please retry." };
  }

  try {
    const fileName = opts.objectPath.split("/").pop() || "capture.m4a";
    const audioBuffer = await data.arrayBuffer();
    const audioBytes = audioBuffer.byteLength;
    const blobType = data.type || "audio/mp4";
    console.log("Voice capture downloaded for transcription", {
      objectPath: opts.objectPath,
      bytes: audioBytes,
      type: blobType,
    });
    const fileBlob = new File([audioBuffer], fileName, { type: blobType });

    const form = new FormData();
    form.append("model", OPENAI_TRANSCRIBE_MODEL);
    form.append("response_format", "json");
    form.append("temperature", "0");
    if (opts.languageHint) {
      form.append("language", opts.languageHint);
    }
    form.append("file", fileBlob);

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${opts.openAiApiKey}`,
      },
      body: form,
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("OpenAI transcription failed", response.status, errText);
      return { text: null, error: `Voice transcription failed (${response.status}).` };
    }

    const json = await response.json();
    const text = typeof json?.text === "string" ? json.text.trim() : "";
    if (!text) {
      console.error("OpenAI transcription returned empty text", { objectPath: opts.objectPath, bytes: audioBytes });
      return { text: null, error: "Voice transcription returned empty text. Try speaking a bit louder/closer." };
    }
    return { text, error: null };
  } catch (error) {
    console.error("Transcription error", error);
    return { text: null, error: "Voice transcription crashed while processing audio. Please retry." };
  }
}

async function deleteUploadedVoiceCaptureIfPresent(
  adminClient: ReturnType<typeof createClient>,
  body: ParseExpenseRequest,
) {
  if (body.source !== "voice") return;
  const objectPath = body.storage_object_path?.trim();
  if (!objectPath) return;

  const bucket = body.storage_bucket?.trim() || VOICE_CAPTURES_BUCKET;
  const { error } = await adminClient.storage.from(bucket).remove([objectPath]);
  if (error) {
    console.error("Failed to delete uploaded voice capture", error.message);
  }
}

function validateRequest(body: ParseExpenseRequest): string | null {
  if (!body.client_expense_id) return "client_expense_id is required";
  if (!body.source) return "source is required";
  if (!body.captured_at_device) return "captured_at_device is required";
  if (body.source === "voice") {
    if (!body.audio_duration_seconds) return "audio_duration_seconds is required for voice";
    if (body.audio_duration_seconds > MAX_VOICE_SECONDS) {
      return `audio_duration_seconds exceeds ${MAX_VOICE_SECONDS}s`;
    }
    const hasRawText = Boolean(body.raw_text?.trim());
    const hasStoragePath = Boolean(body.storage_object_path?.trim());
    if (!hasRawText && !hasStoragePath) {
      return "voice requests require raw_text or storage_object_path";
    }
  }
  if (body.storage_object_path && !body.storage_bucket) {
    // allow default bucket but keep payload explicit if supplied later
  }
  return null;
}

async function getProfile(supabase: ReturnType<typeof createClient>, userId: string): Promise<ProfileRow | null> {
  const { data } = await supabase
    .from("profiles")
    .select("daily_voice_limit, timezone, default_currency")
    .eq("id", userId)
    .maybeSingle();
  return (data ?? null) as ProfileRow | null;
}

async function loadParserCategoryContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<ParserCategoryContext> {
  const { data: categoriesData } = await supabase
    .from("categories")
    .select("id, name, is_default")
    .or(`user_id.is.null,user_id.eq.${userId}`);

  const categoryRows = ((categoriesData ?? []) as CategoryRow[]).filter((row) => !!row?.id && !!row?.name);
  const categoryIDs = categoryRows.map((row) => row.id);

  const { data: hintsData } = categoryIDs.length > 0
    ? await supabase
      .from("category_hints")
      .select("category_id, phrase")
      .eq("user_id", userId)
      .in("category_id", categoryIDs)
    : { data: [] as unknown[] };

  const hints = (hintsData ?? []) as CategoryHintRow[];
  const aliasToCategory: Record<string, string> = { ...CATEGORY_ALIASES };
  const explicitCategoryTokens = new Set<string>([
    ...DEFAULT_CATEGORY_NAMES.map((c) => c.toLowerCase()),
    "bill",
    "bills",
    "utilities",
    "utility",
    "subscription",
    "subscriptions",
  ]);
  const categoryNames = new Set<string>();
  const categoryIDsByName = new Map<string, string>();
  const hintsByCategoryName: Record<string, string[]> = {};

  for (const row of categoryRows) {
    categoryNames.add(row.name);
    categoryIDsByName.set(row.name.toLowerCase(), row.id);
    explicitCategoryTokens.add(row.name.toLowerCase());
  }

  for (const row of categoryRows) {
    const lowerName = row.name.toLowerCase();
    aliasToCategory[lowerName] = row.name;
  }

  for (const hint of hints) {
    const row = categoryRows.find((c) => c.id === hint.category_id);
    if (!row) continue;
    const phrase = hint.phrase.trim().toLowerCase();
    if (!phrase) continue;
    aliasToCategory[phrase] = row.name;
    explicitCategoryTokens.add(phrase);
    hintsByCategoryName[row.name] ??= [];
    if (!hintsByCategoryName[row.name].includes(phrase)) hintsByCategoryName[row.name].push(phrase);
  }

  for (const key of Object.keys(hintsByCategoryName)) {
    hintsByCategoryName[key] = hintsByCategoryName[key].sort();
  }

  return {
    categories: categoryRows.map((row) => ({ id: row.id, name: row.name })),
    categoryNames,
    aliasToCategory,
    explicitCategoryTokens,
    categoryIDsByName,
    hintsByCategoryName,
  };
}

async function loadPaymentMethodContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<ParserPaymentMethodContext> {
  const { data: methodsData } = await supabase
    .from("payment_methods")
    .select("id, name, network, is_active")
    .eq("user_id", userId)
    .eq("is_active", true);

  const methods = ((methodsData ?? []) as PaymentMethodRow[])
    .filter((m) => !!m.id && !!m.name);

  const methodIDs = methods.map((m) => m.id);
  const { data: aliasesData } = methodIDs.length > 0
    ? await supabase
      .from("payment_method_aliases")
      .select("payment_method_id, phrase")
      .eq("user_id", userId)
      .in("payment_method_id", methodIDs)
    : { data: [] as unknown[] };

  const aliases = (aliasesData ?? []) as PaymentMethodAliasRow[];
  const methodsById = new Map<string, { id: string; name: string }>();
  const aliasToMethodIDs = new Map<string, string[]>();

  for (const method of methods) {
    methodsById.set(method.id, { id: method.id, name: method.name });
    for (const alias of normalizePaymentMethodAliases([method.name, method.network ?? ""])) {
      appendAlias(aliasToMethodIDs, alias, method.id);
    }
  }
  for (const aliasRow of aliases) {
    for (const alias of normalizePaymentMethodAliases([aliasRow.phrase])) {
      appendAlias(aliasToMethodIDs, alias, aliasRow.payment_method_id);
    }
  }

  return { methodsById, aliasToMethodIDs };
}

async function validateOwnedRef(
  supabase: ReturnType<typeof createClient>,
  table: "trips" | "payment_methods",
  userId: string,
  id: string | undefined,
): Promise<string | null> {
  if (!id) return null;
  const trimmed = id.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from(table)
    .select("id")
    .eq("user_id", userId)
    .eq("id", trimmed)
    .maybeSingle();
  return (data as { id?: string } | null)?.id ?? null;
}

async function validateCategoryRef(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  id: string | undefined,
): Promise<{ id: string; name: string } | null> {
  if (!id) return null;
  const trimmed = id.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from("categories")
    .select("id, name")
    .eq("id", trimmed)
    .or(`user_id.is.null,user_id.eq.${userId}`)
    .maybeSingle();
  const row = data as { id?: string; name?: string } | null;
  if (!row?.id || !row?.name) return null;
  return { id: row.id, name: row.name };
}

function resolveCategoryIDForParsedCategory(
  categoryName: string,
  ctx: ParserCategoryContext,
): string | null {
  return ctx.categoryIDsByName.get(categoryName.toLowerCase()) ?? null;
}

async function countDailyVoiceUsage(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  capturedAtDevice: string,
  timezone: string,
): Promise<number> {
  const targetLocalDay = localDateKey(capturedAtDevice, timezone);
  const anchor = new Date(capturedAtDevice);
  if (Number.isNaN(anchor.getTime())) return 0;
  const start = new Date(anchor.getTime() - 36 * 60 * 60 * 1000);
  const end = new Date(anchor.getTime() + 36 * 60 * 60 * 1000);

  const { data } = await supabase
    .from("ai_usage_events")
    .select("created_at")
    .eq("user_id", userId)
    .eq("event_type", "voice_parse")
    .gte("created_at", start.toISOString())
    .lt("created_at", end.toISOString());
  const rows = (data ?? []) as Array<{ created_at?: string }>;
  return rows.reduce((count, row) => {
    if (!row.created_at) return count;
    return localDateKey(row.created_at, timezone) === targetLocalDay ? count + 1 : count;
  }, 0);
}

function localDateKey(isoString: string, timeZone: string): string {
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return new Date().toISOString().slice(0, 10);
  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const parts = formatter.formatToParts(date);
    const year = parts.find((p) => p.type === "year")?.value ?? "1970";
    const month = parts.find((p) => p.type === "month")?.value ?? "01";
    const day = parts.find((p) => p.type === "day")?.value ?? "01";
    return `${year}-${month}-${day}`;
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

function normalizePaymentMethodAliases(values: string[]): string[] {
  return values
    .map((v) => v.trim().toLowerCase())
    .filter(Boolean);
}

function appendAlias(map: Map<string, string[]>, alias: string, methodID: string) {
  const existing = map.get(alias) ?? [];
  if (!existing.includes(methodID)) existing.push(methodID);
  map.set(alias, existing);
}

function detectPaymentMethodReference(
  rawText: string,
  ctx: ParserPaymentMethodContext,
): { id: string; name: string } | null {
  if (ctx.aliasToMethodIDs.size === 0) return null;
  const lower = rawText.toLowerCase();
  const matchedMethodIDs = new Set<string>();
  const aliases = Array.from(ctx.aliasToMethodIDs.keys()).sort((a, b) => b.length - a.length);

  for (const alias of aliases) {
    if (!alias) continue;
    const isWordAlias = /^[a-z0-9 ]+$/.test(alias);
    const found = isWordAlias
      ? new RegExp(`\\b${escapeRegex(alias)}\\b`, "i").test(lower)
      : lower.includes(alias);
    if (!found) continue;
    for (const methodID of ctx.aliasToMethodIDs.get(alias) ?? []) {
      matchedMethodIDs.add(methodID);
    }
  }

  if (matchedMethodIDs.size !== 1) return null;
  const methodID = Array.from(matchedMethodIDs)[0];
  return methodID ? (ctx.methodsById.get(methodID) ?? null) : null;
}

function parseExpenseDeterministically(
  rawText: string,
  opts: {
    currencyHint?: string;
    defaultCurrency?: string;
    capturedAtDevice: string;
    categoryContext: ParserCategoryContext;
  },
): DeterministicParse {
  const lower = rawText.toLowerCase();
  const tokens = lower.match(/[a-zA-Z]+|\d+(?:[.,]\d+)?/g) ?? [];

  // Prefer larger/more explicit amounts instead of accidentally capturing a small leading number.
  const amountCandidates = Array.from(rawText.matchAll(/\d+(?:[.,]\d{1,2})?/g)).map((m) => m[0]);
  const amountToken = amountCandidates.sort((a, b) => {
    const aVal = Number(a.replace(",", "."));
    const bVal = Number(b.replace(",", "."));
    return bVal - aVal;
  })[0] ?? null;
  const amountMatch = amountToken ? { 1: amountToken } : null;
  const amount = Number((amountMatch?.[1] ?? "0").replace(",", "."));
  const hasAmount = Number.isFinite(amount) && amount > 0;

  let hasExplicitCurrency = false;
  let currency = (opts.currencyHint ?? opts.defaultCurrency ?? "USD").toUpperCase();
  if (/(peso|pesos|mxn)\b/.test(lower)) {
    currency = "MXN";
    hasExplicitCurrency = true;
  } else if (/(dollar|dollars|usd|\$)\b/.test(lower)) {
    currency = "USD";
    hasExplicitCurrency = true;
  } else if (/\beur|euro|euros\b/.test(lower)) {
    currency = "EUR";
    hasExplicitCurrency = true;
  }
  const usedDefaultCurrency = !hasExplicitCurrency;

  let category = "Other";
  let hasExplicitCategory = false;
  const phraseAliases = Object.entries(opts.categoryContext.aliasToCategory)
    .filter(([phrase]) => phrase.includes(" "))
    .sort((a, b) => b[0].length - a[0].length);
  for (const [phrase, mappedCategory] of phraseAliases) {
    if (lower.includes(phrase)) {
      category = mappedCategory;
      hasExplicitCategory = true;
      break;
    }
  }

  for (const token of tokens) {
    if (category !== "Other") break;
    const alias = opts.categoryContext.aliasToCategory[token];
    if (alias) {
      category = alias;
      hasExplicitCategory = opts.categoryContext.explicitCategoryTokens.has(token)
        || hasExplicitCategory;
      if (category !== "Other") break;
    }
  }
  if (!opts.categoryContext.categoryNames.has(category)) category = "Other";

  const expenseDate = inferExpenseDate(rawText, opts.capturedAtDevice);
  const builtDescription = buildDescription(rawText, {
    amountMatch: amountMatch?.[1] ?? null,
    category,
    aliasToCategory: opts.categoryContext.aliasToCategory,
  });
  const refinedNarrative = refineParsedNarrative({
    rawText,
    category,
    description: builtDescription,
    merchant: null,
  });

  let confidence = 0.7;
  if (hasAmount) confidence += 0.12;
  if (category !== "Other") confidence += 0.08;
  if (hasExplicitCategory) confidence += 0.07;
  if (hasExplicitCurrency) confidence += 0.04;
  if (tokens.length >= 3) confidence += 0.03;
  if (tokens.length >= 5) confidence += 0.03;
  const normalizedDescription = refinedNarrative.description.toLowerCase().trim();
  if (hasAmount && category !== "Other" && normalizedDescription.length >= 3 && normalizedDescription !== "on") {
    confidence += 0.04;
  }
  if (!hasAmount) confidence -= 0.1;
  if (category === "Other" && !hasExplicitCategory) confidence -= 0.04;
  if (usedDefaultCurrency) confidence -= 0.02;

  return {
    parsed: {
      amount: hasAmount ? amount : 1,
      currency,
      category,
      description: refinedNarrative.description,
      merchant: refinedNarrative.merchant,
      expense_date: expenseDate,
    },
    confidence: clamp(confidence, 0.4, 0.99),
    metadata: {
      hasAmount,
      hasExplicitCurrency,
      usedDefaultCurrency,
      hasExplicitCategory,
      tokenCount: tokens.length,
    },
  };
}

function shouldUseAiFallback(deterministic: DeterministicParse): boolean {
  const { confidence, metadata, parsed } = deterministic;
  // Product behavior: if deterministic is not good enough to auto-save, let AI try first.
  if (confidence < AUTO_SAVE_CONFIDENCE_THRESHOLD) return true;
  if (!metadata.hasAmount) return true;
  if (parsed.category === "Other" && !metadata.hasExplicitCategory) return true;
  const desc = (parsed.description ?? "").trim().toLowerCase();
  if (!desc || desc.length < 3) return true;
  if (/^(on|at|in|for|with)$/i.test(desc)) return true;
  return false;
}

async function parseExpenseWithOpenAI(opts: {
  apiKey: string | undefined;
  rawText: string;
  capturedAtDevice: string;
  currencyHint?: string;
  languageHint?: "en" | "es";
  defaultCurrency?: string;
  categoryContext: ParserCategoryContext;
}): Promise<ParseOutcome | null> {
  if (!opts.apiKey) return null;

  const fallbackDate = new Date(opts.capturedAtDevice).toISOString().slice(0, 10);
  const defaultCurrency = (opts.currencyHint ?? opts.defaultCurrency ?? "USD").toUpperCase();
  const outputLanguageHint = normalizeLanguageHint(opts.languageHint);

  const allowedCategories = opts.categoryContext.categories.map((c) => c.name);
  const categoryHintsText = opts.categoryContext.categories
    .map((c) => {
      const hints = opts.categoryContext.hintsByCategoryName[c.name] ?? [];
      return hints.length ? `- ${c.name}: ${hints.slice(0, 20).join(", ")}` : `- ${c.name}`;
    })
    .join("\n");

  const prompt = [
    "Extract one personal expense from the user text.",
    "Return JSON only with keys: amount, currency, category, description, merchant, expense_date, confidence.",
    "Rules:",
    "- amount: number > 0",
    `- currency: ISO code, default to ${defaultCurrency} when omitted`,
    `- category: one of ${allowedCategories.join(", ")}`,
    `- expense_date: YYYY-MM-DD, default to ${fallbackDate} if not specified`,
    "- confidence: number 0 to 1",
    "- merchant can be null",
    "- description should be concise and useful (3-10 words when possible), remove filler words and rambling",
    `- language: keep description/merchant in the user's language${outputLanguageHint ? ` (preferred: ${outputLanguageHint})` : " when clear"}`,
    "- if the user mentions a place/restaurant/store, put it in merchant",
    "- good description example: 'Food with friends at Peter Piper Pizza'",
    "Available categories and examples:",
    categoryHintsText,
    `User text: ${opts.rawText}`,
  ].join("\n");

  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opts.apiKey}`,
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: "You parse personal finance expense messages into strict JSON.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
      }),
    });

    if (!res.ok) {
      console.error("OpenAI fallback failed", res.status, await res.text());
      return null;
    }

    const payload = await res.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string") return null;

    const parsedJson = JSON.parse(content);
    const normalized = normalizeParsedExpense(parsedJson, {
      rawText: opts.rawText,
      fallbackDate,
      defaultCurrency,
      languageHint: outputLanguageHint,
      categoryContext: opts.categoryContext,
    });
    if (!normalized) return null;

    const confidence = typeof parsedJson?.confidence === "number"
      ? clamp(parsedJson.confidence, 0.5, 0.99)
      : 0.94;

    return {
      parsed: normalized,
      confidence,
      provider: "openai",
      model: OPENAI_MODEL,
    };
  } catch (error) {
    console.error("OpenAI fallback error", error);
    return null;
  }
}

function normalizeParsedExpense(
  input: unknown,
  opts: {
    rawText: string;
    fallbackDate: string;
    defaultCurrency: string;
    languageHint?: "en" | "es";
    categoryContext: ParserCategoryContext;
  },
): ParsedExpense | null {
  if (!input || typeof input !== "object") return null;
  const record = input as Record<string, unknown>;

  const amount = typeof record.amount === "number"
    ? record.amount
    : typeof record.amount === "string"
    ? Number(record.amount.replace(",", "."))
    : NaN;
  if (!Number.isFinite(amount) || amount <= 0) return null;

  const currencyRaw = typeof record.currency === "string" ? record.currency.trim().toUpperCase() : "";
  const currency = /^[A-Z]{3}$/.test(currencyRaw) ? currencyRaw : opts.defaultCurrency;

  const categoryRaw = typeof record.category === "string" ? record.category.trim() : "Other";
  const category = normalizeCategory(categoryRaw, opts.categoryContext);

  const descriptionRaw = typeof record.description === "string" ? record.description.trim() : "";
  const merchantRaw = typeof record.merchant === "string"
    ? record.merchant.trim() || null
    : null;
  const refined = refineParsedNarrative({
    rawText: opts.rawText,
    category,
    description: descriptionRaw || opts.rawText,
    merchant: merchantRaw,
    languageHint: opts.languageHint,
  });

  const dateRaw = typeof record.expense_date === "string" ? record.expense_date.trim() : "";
  const expenseDate = /^\d{4}-\d{2}-\d{2}$/.test(dateRaw) ? dateRaw : opts.fallbackDate;

  return {
    amount,
    currency,
    category,
    description: refined.description,
    merchant: refined.merchant,
    expense_date: expenseDate,
  };
}

function normalizeCategory(value: string, ctx: ParserCategoryContext): string {
  if (ctx.categoryNames.has(value)) return value;
  const lower = value.toLowerCase();
  if (lower in ctx.aliasToCategory) {
    return ctx.aliasToCategory[lower] ?? "Other";
  }
  return "Other";
}

function inferExpenseDate(rawText: string, capturedAtDevice: string): string {
  const base = new Date(capturedAtDevice);
  if (Number.isNaN(base.getTime())) return new Date().toISOString().slice(0, 10);
  const lower = rawText.toLowerCase();
  if (lower.includes("yesterday")) {
    base.setUTCDate(base.getUTCDate() - 1);
  } else if (lower.includes("today")) {
    // explicit today; no-op
  }
  return base.toISOString().slice(0, 10);
}

function buildDescription(
  rawText: string,
  opts: { amountMatch: string | null; category: string; aliasToCategory: Record<string, string> },
): string {
  let text = rawText.trim();
  if (opts.amountMatch) {
    text = text.replace(opts.amountMatch, "").replace(/\s{2,}/g, " ").trim();
  }

  const categoryWords = Object.entries(opts.aliasToCategory)
    .filter(([, category]) => category === opts.category)
    .map(([word]) => word)
    .sort((a, b) => b.length - a.length);

  for (const word of categoryWords) {
    const re = new RegExp(`\\b${escapeRegex(word)}\\b`, "ig");
    text = text.replace(re, " ");
  }

  // Remove common expense verbs and filler words that do not help the description.
  text = text
    .replace(/\b(i|me|my)\b/gi, " ")
    .replace(/\b(spent|spend|paid|pay|bought|buy|purchase|purchased|cost|for)\b/gi, " ")
    .replace(/\b(on)\b(?=\s+(?:at|in)\b)/gi, " ")
    .replace(/\b(on)\b$/gi, " ");

  text = text.replace(/\s{2,}/g, " ").trim();
  // If the description is just glue words, keep a cleaner fallback.
  if (/^(on|at|in|for|with)$/i.test(text)) {
    text = "";
  }
  return text || rawText.trim();
}

function normalizeLanguageHint(value: unknown): "en" | "es" | undefined {
  if (value === "en" || value === "es") return value;
  return undefined;
}

function refineParsedNarrative(opts: {
  rawText: string;
  category: string;
  description: string;
  merchant: string | null;
  languageHint?: "en" | "es";
}): { description: string; merchant: string | null } {
  const rawText = opts.rawText.trim();
  const language = opts.languageHint ?? inferLanguageFromText(rawText);
  const merchant = normalizeMerchantName(opts.merchant) ?? extractMerchantFromText(rawText) ?? extractMerchantFromText(opts.description);
  const hasFriends = /\b(friends?|amigos?|compas|banda)\b/i.test(rawText);

  const cleanedDescription = compactDescriptionText(opts.description || rawText)
    || compactDescriptionText(rawText)
    || opts.category;

  const shouldComposeCanonical =
    hasFriends ||
    Boolean(merchant) ||
    cleanedDescription.length > 52 ||
    cleanedDescription.toLowerCase() === rawText.toLowerCase() ||
    /\b(um+|uh+|like|este+|eh+|mmm+)\b/i.test(rawText);

  let description = cleanedDescription;
  if (shouldComposeCanonical) {
    description = composeSmartDescription({
      category: opts.category,
      merchant,
      hasFriends,
      language,
      fallback: cleanedDescription,
    });
  }

  return {
    description: description.slice(0, 90).trim(),
    merchant,
  };
}

function composeSmartDescription(opts: {
  category: string;
  merchant: string | null;
  hasFriends: boolean;
  language?: "en" | "es";
  fallback: string;
}): string {
  const useSpanish = opts.language === "es";
  if (opts.merchant && opts.hasFriends) {
    return useSpanish
      ? `${opts.category} con amigos en ${opts.merchant}`
      : `${opts.category} with friends at ${opts.merchant}`;
  }
  if (opts.merchant) {
    return useSpanish
      ? `${opts.category} en ${opts.merchant}`
      : `${opts.category} at ${opts.merchant}`;
  }
  if (opts.hasFriends) {
    return useSpanish
      ? `${opts.category} con amigos`
      : `${opts.category} with friends`;
  }
  return opts.fallback || opts.category;
}

function compactDescriptionText(input: string): string {
  let text = input.trim();
  if (!text) return "";

  text = text
    .replace(/\b\d+(?:[.,]\d{1,2})?\b/g, " ")
    .replace(/\b(mxn|usd|eur|gbp|jpy|cad|brl)\b/gi, " ")
    .replace(/[€$£¥]/g, " ")
    .replace(/\b(peso|pesos|dollar|dollars|euro|euros|pound|pounds|yen)\b/gi, " ")
    .replace(/\b(umm+|um+|uh+|mmm+|like|you know|kinda|sorta)\b/gi, " ")
    .replace(/\b(este+|eh+|pues|osea|o sea|como que|esteem?)\b/gi, " ")
    .replace(/\b(i|we|my|me|yo|nosotros|nosotras|con mis|con mi)\b/gi, " ")
    .replace(/\b(went|go|going|salí|sali|fuí|fui|fuimos|iba|went out|go out)\b/gi, " ")
    .replace(/\b(spent|spend|paid|pay|bought|buy|purchase|purchased|cost)\b/gi, " ")
    .replace(/\b(gast[ée]|gaste|pagu[ée]|pague|compr[ée]|compre|cost[oó])\b/gi, " ")
    .replace(/\b(on|for|to|the|and|then|that|a|an)\b/gi, " ")
    .replace(/\b(en|para|por|y|que|de|del|la|el|los|las|un|una)\b/gi, " ")
    .replace(/\s{2,}/g, " ")
    .trim();

  text = text.replace(/^[,.;:\-]+|[,.;:\-]+$/g, "").trim();
  if (!text) return "";
  if (/^(at|in|with|on|en|con|para|por)$/i.test(text)) return "";
  return capitalizeFirst(text);
}

function extractMerchantFromText(input: string): string | null {
  const patterns = [
    /\b(?:at|en)\s+([A-Za-zÀ-ÿ0-9&'".\- ]{2,48})/i,
    /\b(?:from|de)\s+([A-Za-zÀ-ÿ0-9&'".\- ]{2,48})/i,
  ];

  for (const pattern of patterns) {
    const match = input.match(pattern);
    const raw = match?.[1]?.trim();
    if (!raw) continue;
    const merchant = raw
      .replace(/\b(?:with|con|for|por|and|y)\b.*$/i, "")
      .replace(/[.,;:]+$/g, "")
      .trim();
    if (!merchant) continue;
    if (/^(food|transport|shopping|entertainment|other|groceries|utilities|subscriptions)$/i.test(merchant)) continue;
    return normalizeMerchantName(merchant);
  }
  return null;
}

function normalizeMerchantName(value: string | null | undefined): string | null {
  const trimmed = (value ?? "").trim().replace(/\s{2,}/g, " ");
  if (!trimmed) return null;
  if (trimmed.length > 50) return trimmed.slice(0, 50).trim();
  return trimmed;
}

function inferLanguageFromText(text: string): "en" | "es" | undefined {
  const lower = text.toLowerCase();
  const spanishSignals = [
    /\b(gaste|gast[eé]|pague|pagu[eé]|compre|compr[eé]|amigos|restaurante|comida|uber)\b/i,
    /\b(hoy|ayer|mañana|anoche|con|en|para|por)\b/i,
  ];
  if (spanishSignals.some((re) => re.test(lower))) return "es";
  const englishSignals = [/\b(spent|paid|bought|friends|yesterday|today|tonight)\b/i];
  if (englishSignals.some((re) => re.test(lower))) return "en";
  return undefined;
}

function capitalizeFirst(text: string): string {
  if (!text) return text;
  return text[0].toUpperCase() + text.slice(1);
}

function isVoicePlaceholderText(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  return normalized === "voice recording";
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function json(body: ParseExpenseResponse, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
