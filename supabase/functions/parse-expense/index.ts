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
const PRIMARY_AUTH_STRATEGY = "adminClient.auth.getUser";

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
    "comida", "comidas", "almuerzo", "desayuno", "cena",
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
  user_id: string | null;
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
    amountToken: string | null;
    amountScore: number;
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
  let cleanupClient: ReturnType<typeof createClient> | null = null;
  let cleanupBody: ParseExpenseRequest | null = null;
  let cleanupUserID: string | null = null;
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
    cleanupClient = adminClient;
    if (!bearerToken) {
      return json(
        { status: "error", error: "Unauthorized" } satisfies ParseExpenseResponse,
        401,
      );
    }

    const authResolution = await validateUserFromBearerToken({
      supabaseUrl,
      supabaseAnonKey,
      adminClient,
      bearerToken,
    });
    const authAttempts = summarizeAuthAttempts(authResolution.attempts);
    if (!authResolution.user) {
      console.error(
        "[parse-expense] auth validation failed",
        {
          reason: authResolution.error ?? "Unauthorized",
          attempts: authAttempts,
        },
      );
      return json(
        { status: "error", error: authResolution.error || "Unauthorized" } satisfies ParseExpenseResponse,
        401,
      );
    }
    const authLog = {
      strategy: authResolution.strategy,
      attempts: authAttempts,
      userTail: authResolution.user.id.slice(-8),
    };
    if (authResolution.strategy !== PRIMARY_AUTH_STRATEGY) {
      console.warn("[parse-expense] auth fallback strategy used", authLog);
    } else {
      console.log("[parse-expense] auth validation succeeded", authLog);
    }
    const user = authResolution.user;
    cleanupUserID = user.id;

    const body = (await req.json()) as ParseExpenseRequest;
    cleanupBody = body;
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
    const profileTimezone = resolveTimeZone(profile?.timezone);
    const requestTimezone = resolveTimeZone(body.timezone);
    const quotaTimeZone = profileTimezone ?? "UTC";
    const tz = requestTimezone ?? profileTimezone ?? "UTC";

    const dailyVoiceUsed = await countDailyVoiceUsage(
      adminClient,
      user.id,
      quotaTimeZone,
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
      userID: user.id,
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

    const deterministic = parseExpenseDeterministically(rawText, {
      currencyHint: body.currency_hint,
      defaultCurrency: profile?.default_currency ?? undefined,
      capturedAtDevice: body.captured_at_device,
      timezone: tz,
      categoryContext: parserCategoryContext,
    });

    const aiOutcome = await parseExpenseWithOpenAI({
      apiKey: openAiApiKey,
      rawText,
      capturedAtDevice: body.captured_at_device,
      timezone: tz,
      currencyHint: body.currency_hint,
      languageHint: body.language_hint,
      defaultCurrency: profile?.default_currency ?? undefined,
      categoryContext: parserCategoryContext,
    });

    let outcome: ParseOutcome;
    if (aiOutcome) {
      outcome = aiOutcome;
    } else {
      outcome = {
        parsed: deterministic.parsed,
        confidence: deterministic.confidence,
        provider: "deterministic",
        model: "rules-v1",
      };
    }
    outcome.parsed = applyStrictPostValidation({
      parsed: outcome.parsed,
      rawText,
      languageHint: body.language_hint,
      paymentMethodContext: parserPaymentMethodContext,
    });

    const needsReview = outcome.confidence < AUTO_SAVE_CONFIDENCE_THRESHOLD || body.allow_auto_save === false;

    const parsedCategoryId = resolveCategoryIDForParsedCategory(outcome.parsed.category, parserCategoryContext);
    const categoryRef = await validateCategoryRef(adminClient, user.id, body.category_id);
    const finalCategoryId = categoryRef?.id ?? parsedCategoryId;
    const finalCategoryName = categoryRef?.name ?? outcome.parsed.category;
    let tripRef = await validateOwnedTripRef(adminClient, user.id, body.trip_id);
    if (!tripRef) {
        tripRef = await resolveTripRefFromNameIfUnique(adminClient, user.id, body.trip_name);
    }
    const finalTripName = tripRef?.name ?? (body.trip_name?.trim() || null);
    const detectedPaymentMethod = detectPaymentMethodReference(rawText, parserPaymentMethodContext);
    let paymentMethodRef = await validateOwnedPaymentMethodRef(
      adminClient,
      user.id,
      body.payment_method_id ?? detectedPaymentMethod?.id,
    );
    if (!paymentMethodRef) {
        paymentMethodRef = await resolvePaymentMethodRefFromNameIfUnique(adminClient, user.id, body.payment_method_name);
    }
    const finalPaymentMethodName = paymentMethodRef?.name ?? (body.payment_method_name?.trim() || null);
    const parseStatus = needsReview ? "needs_review" : "auto";

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
          trip_id: tripRef?.id ?? null,
          trip_name: finalTripName,
          payment_method_id: paymentMethodRef?.id ?? null,
          payment_method_name: finalPaymentMethodName,
          expense_date: outcome.parsed.expense_date,
          captured_at_device: body.captured_at_device,
          synced_at: new Date().toISOString(),
          source: body.source,
          parse_status: parseStatus,
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

    const didCountUsageEvent = await recordUsageEventIfNeeded({
      supabase: adminClient,
      userID: user.id,
      clientExpenseID: body.client_expense_id,
      source: body.source,
      provider: outcome.provider,
      model: outcome.model,
      audioDurationSeconds: body.audio_duration_seconds ?? null,
    });

    const response: ParseExpenseResponse = {
      status: needsReview ? "needs_review" : "saved",
      expense: savedExpense,
      parse: {
        confidence: outcome.confidence,
        raw_text: rawText,
        needs_review: needsReview,
      },
      usage: {
        daily_voice_used: body.source === "voice" ? dailyVoiceUsed + (didCountUsageEvent ? 1 : 0) : dailyVoiceUsed,
        daily_voice_limit: dailyVoiceLimit,
      },
    };

    return json(response, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ status: "error", error: message } satisfies ParseExpenseResponse, 500);
  } finally {
    if (cleanupClient && cleanupBody && cleanupUserID) {
      await deleteUploadedVoiceCaptureIfPresent(cleanupClient, cleanupBody, cleanupUserID);
    }
  }
});

async function recordUsageEventIfNeeded(opts: {
  supabase: ReturnType<typeof createClient>;
  userID: string;
  clientExpenseID: string;
  source: ParseExpenseRequest["source"];
  provider: string;
  model: string;
  audioDurationSeconds: number | null;
}): Promise<boolean> {
  const eventType = opts.source === "voice" ? "voice_parse" : "text_parse";
  const { error } = await opts.supabase.from("ai_usage_events").insert({
    user_id: opts.userID,
    client_expense_id: opts.clientExpenseID,
    event_type: eventType,
    provider: opts.provider,
    model: opts.model,
    audio_seconds: opts.audioDurationSeconds,
    estimated_cost_usd: opts.provider === "openai" ? null : 0,
  });
  if (!error) return true;

  const duplicate = error.code === "23505"
    || (error.message?.toLowerCase().includes("duplicate key") ?? false);
  if (duplicate) {
    return false;
  }

  console.error("[parse-expense] failed to store ai usage event", {
    userID: opts.userID,
    clientExpenseID: opts.clientExpenseID,
    eventType,
    code: error.code,
    message: error.message,
  });
  return false;
}

async function resolveInputText(opts: {
  body: ParseExpenseRequest;
  adminClient: ReturnType<typeof createClient>;
  openAiApiKey: string | undefined;
  userID: string;
}): Promise<{ text: string | null; error: string | null }> {
  const rawTextCandidate = opts.body.raw_text?.trim();
  const rawText = rawTextCandidate && !isVoicePlaceholderText(rawTextCandidate) ? rawTextCandidate : null;
  if (opts.body.source !== "voice") {
    return { text: rawText ?? null, error: null };
  }

  const storageObjectPath = opts.body.storage_object_path?.trim();
  if (storageObjectPath) {
    const requestedBucket = opts.body.storage_bucket?.trim();
    if (requestedBucket && requestedBucket !== VOICE_CAPTURES_BUCKET) {
      return { text: null, error: "Invalid voice storage bucket." };
    }
    if (!storageObjectPath.startsWith(`${opts.userID}/`)) {
      return { text: null, error: "Invalid voice storage object path." };
    }

    const transcribed = await transcribeVoiceCaptureFromStorage({
      adminClient: opts.adminClient,
      openAiApiKey: opts.openAiApiKey,
      bucket: VOICE_CAPTURES_BUCKET,
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
  userID: string,
) {
  if (body.source !== "voice") return;
  const objectPath = body.storage_object_path?.trim();
  if (!objectPath) return;
  if (!objectPath.startsWith(`${userID}/`)) return;

  const { error } = await adminClient.storage.from(VOICE_CAPTURES_BUCKET).remove([objectPath]);
  if (error) {
    console.error("Failed to delete uploaded voice capture", error.message);
  }
}

function validateRequest(body: ParseExpenseRequest): string | null {
  if (!body.client_expense_id) return "client_expense_id is required";
  if (!body.source) return "source is required";
  if (!body.captured_at_device) return "captured_at_device is required";
  if (body.source === "voice") {
    if (typeof body.audio_duration_seconds !== "number" || !Number.isFinite(body.audio_duration_seconds)) {
      return "audio_duration_seconds is required for voice";
    }
    if (!Number.isInteger(body.audio_duration_seconds)) {
      return "audio_duration_seconds must be an integer";
    }
    if (body.audio_duration_seconds < 1) {
      return "audio_duration_seconds must be at least 1s";
    }
    if (body.audio_duration_seconds > MAX_VOICE_SECONDS) {
      return `audio_duration_seconds exceeds ${MAX_VOICE_SECONDS}s`;
    }
    const hasRawText = Boolean(body.raw_text?.trim());
    const hasStoragePath = Boolean(body.storage_object_path?.trim());
    if (!hasRawText && !hasStoragePath) {
      return "voice requests require raw_text or storage_object_path";
    }
  }
  if (body.storage_bucket) {
    const requestedBucket = body.storage_bucket.trim();
    if (requestedBucket && requestedBucket !== VOICE_CAPTURES_BUCKET) {
      return "storage_bucket must be voice-captures";
    }
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
  const [systemCategoriesResult, userCategoriesResult] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name, is_default, user_id")
      .is("user_id", null),
    supabase
      .from("categories")
      .select("id, name, is_default, user_id")
      .eq("user_id", userId),
  ]);

  const categoryRowsByID = new Map<string, CategoryRow>();
  for (const row of [...(systemCategoriesResult.data ?? []), ...(userCategoriesResult.data ?? [])] as CategoryRow[]) {
    if (!row?.id || !row?.name) continue;
    categoryRowsByID.set(row.id, row);
  }
  const categoryRows = Array.from(categoryRowsByID.values());
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

async function validateOwnedPaymentMethodRef(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  id: string | undefined,
): Promise<{ id: string; name: string } | null> {
  if (!id) return null;
  const trimmed = id.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from("payment_methods")
    .select("id, name")
    .eq("user_id", userId)
    .eq("id", trimmed)
    .maybeSingle();
  const row = data as { id?: string; name?: string } | null;
  if (!row?.id || !row?.name) return null;
  return { id: row.id, name: row.name };
}

async function resolvePaymentMethodRefFromNameIfUnique(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  paymentMethodName: string | undefined,
): Promise<{ id: string; name: string } | null> {
  const trimmed = paymentMethodName?.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from("payment_methods")
    .select("id, name")
    .eq("user_id", userId)
    .ilike("name", trimmed)
    .eq("is_active", true)
    .order("created_at", { ascending: false });
  const rows = (data ?? []) as Array<{ id?: string; name?: string }>;
  if (rows.length !== 1) return null;
  const row = rows[0];
  if (!row?.id || !row?.name) return null;
  return { id: row.id, name: row.name };
}

async function validateOwnedTripRef(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  id: string | undefined,
): Promise<{ id: string; name: string } | null> {
  if (!id) return null;
  const trimmed = id.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from("trips")
    .select("id, name")
    .eq("user_id", userId)
    .eq("id", trimmed)
    .maybeSingle();
  const row = data as { id?: string; name?: string } | null;
  if (!row?.id || !row?.name) return null;
  return { id: row.id, name: row.name };
}

async function resolveTripRefFromNameIfUnique(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tripName: string | undefined,
): Promise<{ id: string; name: string } | null> {
  const trimmed = tripName?.trim();
  if (!trimmed) return null;
  const { data } = await supabase
    .from("trips")
    .select("id, name")
    .eq("user_id", userId)
    .ilike("name", trimmed)
    .order("status", { ascending: false })
    .order("created_at", { ascending: false });
  const rows = (data ?? []) as Array<{ id?: string; name?: string }>;
  if (rows.length !== 1) return null;
  const row = rows[0];
  if (!row?.id || !row?.name) return null;
  return { id: row.id, name: row.name };
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
    .select("id, name, user_id")
    .eq("id", trimmed)
    .maybeSingle();
  const row = data as { id?: string; name?: string; user_id?: string | null } | null;
  if (!row?.id || !row?.name) return null;
  const ownerID = row.user_id ?? null;
  if (ownerID !== null && ownerID !== userId) return null;
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
  timezone: string,
): Promise<number> {
  // Enforce quota by server-observed day in the user's timezone (tamper-resistant).
  const now = new Date();
  const targetLocalDay = localDateKey(now.toISOString(), timezone);
  const start = new Date(now.getTime() - 36 * 60 * 60 * 1000);
  const end = new Date(now.getTime() + 36 * 60 * 60 * 1000);

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
  if (Number.isNaN(date.getTime())) return dateKeyInTimeZone(new Date(), timeZone);
  return dateKeyInTimeZone(date, timeZone);
}

function resolveTimeZone(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  try {
    // Throws for invalid or unsupported zone names.
    new Intl.DateTimeFormat("en-US", { timeZone: trimmed }).format(new Date());
    return trimmed;
  } catch {
    return null;
  }
}

function dateKeyInTimeZone(date: Date, timeZone: string): string {
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

function parseLocalizedNumberToken(value: string): number | null {
  let cleaned = value
    .trim()
    .replace(/\s+/g, "")
    .replace(/[’']/g, "");
  if (!/\d/.test(cleaned)) return null;

  const commaCount = (cleaned.match(/,/g) ?? []).length;
  const dotCount = (cleaned.match(/\./g) ?? []).length;
  let decimalSeparator: "," | "." | null = null;

  if (commaCount > 0 && dotCount > 0) {
    const lastComma = cleaned.lastIndexOf(",");
    const lastDot = cleaned.lastIndexOf(".");
    decimalSeparator = lastComma > lastDot ? "," : ".";
  } else if (commaCount === 1) {
    const separatorIndex = cleaned.lastIndexOf(",");
    const suffixDigits = cleaned.length - separatorIndex - 1;
    decimalSeparator = suffixDigits === 3 ? null : ",";
  } else if (dotCount === 1) {
    const separatorIndex = cleaned.lastIndexOf(".");
    const suffixDigits = cleaned.length - separatorIndex - 1;
    decimalSeparator = suffixDigits === 3 ? null : ".";
  }

  if (decimalSeparator) {
    const thousandsSeparator = decimalSeparator === "," ? "." : ",";
    cleaned = cleaned.split(thousandsSeparator).join("");
    if (decimalSeparator === ",") {
      cleaned = cleaned.replace(",", ".");
    }
  } else {
    cleaned = cleaned.replace(/[.,]/g, "");
  }

  if (cleaned.endsWith(".")) cleaned += "0";
  const parsed = Number(cleaned);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

type AmountCandidate = {
  token: string;
  value: number;
  score: number;
  index: number;
};

function selectAmountCandidate(rawText: string): AmountCandidate | null {
  const candidates = Array.from(
    rawText.matchAll(/\d{1,3}(?:[.,\s'’]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?/g),
  ).flatMap((match): AmountCandidate[] => {
    const token = match[0];
    const value = parseLocalizedNumberToken(token);
    const index = match.index ?? -1;
    if (value === null || index < 0) return [];
    const score = scoreAmountCandidate(rawText, token, value, index);
    return [{ token, value, score, index }];
  });

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => {
    if (a.score !== b.score) return b.score - a.score;
    if (a.value !== b.value) return b.value - a.value;
    return b.token.length - a.token.length;
  });
  return candidates[0] ?? null;
}

function scoreAmountCandidate(rawText: string, token: string, value: number, index: number): number {
  let score = 0;
  if (/[.,]\d{1,2}$/.test(token)) score += 30;
  if (/[.,\s'’]\d{3}/.test(token)) score += 15;
  if (/[$€£¥]/.test(token)) score += 25;

  const start = Math.max(0, index - 12);
  const end = Math.min(rawText.length, index + token.length + 12);
  const contextWindow = rawText.slice(start, end).toLowerCase();
  if (/\b(usd|mxn|eur|gbp|jpy|cad|brl|peso|pesos|dollar|dollars|euro|euros)\b/.test(contextWindow)) {
    score += 40;
  }

  const sanitized = token.replace(/[,\s'’.]/g, "");
  if (sanitized.length === 4 && value >= 1900 && value <= 2100) {
    score -= 90;
  }
  if (isLikelyDateNumber(rawText, index, token.length)) {
    score -= 120;
  }
  if (value > 500_000) {
    score -= 50;
  }
  return score;
}

function isLikelyDateNumber(text: string, index: number, length: number): boolean {
  const start = Math.max(0, index - 8);
  const end = Math.min(text.length, index + length + 8);
  const snippet = text.slice(start, end);
  return /\d{1,4}\s*[-/]\s*\d{1,2}\s*[-/]\s*\d{1,4}/.test(snippet)
    || /\d{1,2}\s*[-/]\s*\d{1,2}/.test(snippet);
}

function parseExpenseDeterministically(
  rawText: string,
  opts: {
    currencyHint?: string;
    defaultCurrency?: string;
    capturedAtDevice: string;
    timezone: string;
    categoryContext: ParserCategoryContext;
  },
): DeterministicParse {
  const lower = rawText.toLowerCase();
  const tokens = lower.match(/[a-zA-Z]+|\d+(?:[.,]\d+)?/g) ?? [];

  const amountCandidate = selectAmountCandidate(rawText);
  const amountMatch = amountCandidate?.token ?? null;
  const amount = amountCandidate?.value ?? 0;
  const hasAmount = Number.isFinite(amount) && amount > 0;
  const amountScore = amountCandidate?.score ?? 0;

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

  const expenseDate = inferExpenseDate(rawText, opts.capturedAtDevice, opts.timezone);
  const builtDescription = buildDescription(rawText, {
    amountMatch,
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
      amountToken: amountMatch,
      amountScore,
      hasExplicitCurrency,
      usedDefaultCurrency,
      hasExplicitCategory,
      tokenCount: tokens.length,
    },
  };
}

async function parseExpenseWithOpenAI(opts: {
  apiKey: string | undefined;
  rawText: string;
  capturedAtDevice: string;
  timezone: string;
  currencyHint?: string;
  languageHint?: "en" | "es";
  defaultCurrency?: string;
  categoryContext: ParserCategoryContext;
}): Promise<ParseOutcome | null> {
  if (!opts.apiKey) return null;

  const fallbackDate = localDateKey(opts.capturedAtDevice, opts.timezone);
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
    "- never use payment method/card words as merchant (e.g. card, tarjeta, Amex, Visa, Mastercard)",
    "- merchant must be the business/place only; if unclear return null",
    "- description should be concise and useful (3-10 words when possible), remove filler words and rambling",
    "- description should not include amounts or payment method phrases",
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

function inferExpenseDate(rawText: string, capturedAtDevice: string, timezone = "UTC"): string {
  const base = new Date(capturedAtDevice);
  if (Number.isNaN(base.getTime())) return localDateKey(new Date().toISOString(), timezone);
  const lower = rawText.toLowerCase();
  if (lower.includes("yesterday")) {
    base.setUTCDate(base.getUTCDate() - 1);
  }
  return localDateKey(base.toISOString(), timezone);
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

function applyStrictPostValidation(opts: {
  parsed: ParsedExpense;
  rawText: string;
  languageHint?: "en" | "es";
  paymentMethodContext: ParserPaymentMethodContext;
}): ParsedExpense {
  const language = normalizeLanguageHint(opts.languageHint) ?? inferLanguageFromText(opts.rawText);
  const paymentMethodTokens = buildPaymentMethodNoiseTokens(opts.paymentMethodContext);

  const merchant = sanitizeMerchantStrict(opts.parsed.merchant, paymentMethodTokens);
  const narrative = refineParsedNarrative({
    rawText: opts.rawText,
    category: opts.parsed.category,
    description: opts.parsed.description ?? opts.rawText,
    merchant,
    languageHint: language,
  });

  const description = sanitizeDescriptionStrict({
    description: narrative.description,
    rawText: opts.rawText,
    category: opts.parsed.category,
    merchant,
    language,
    paymentMethodTokens,
  });

  return {
    ...opts.parsed,
    description,
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

function sanitizeDescriptionStrict(opts: {
  description: string;
  rawText: string;
  category: string;
  merchant: string | null;
  language?: "en" | "es";
  paymentMethodTokens: Set<string>;
}): string {
  const cleaned = opts.description.trim().replace(/\s{2,}/g, " ");
  const lower = cleaned.toLowerCase();
  const rawLower = opts.rawText.trim().toLowerCase();

  const hasAmountNoise = /\d{1,3}(?:[.,\s'’]\d{3})*(?:[.,]\d{1,2})?/.test(cleaned)
    || /\b(peso|pesos|mxn|usd|eur|gbp|jpy|cad|brl|dollar|dollars|euro|euros)\b/i.test(cleaned);
  const hasPaymentNoise = containsAnyPhrase(lower, opts.paymentMethodTokens);
  const hasVerbNoise = /\b(me gast[ée]|gast[ée]|gaste|pagu[ée]|pague|compr[ée]|compre|spent|paid|bought)\b/i.test(cleaned);
  const wordCount = cleaned.split(/\s+/).filter(Boolean).length;
  const looksLikeRaw = lower === rawLower || (rawLower.length > 18 && lower.includes(rawLower));
  const tooShort = wordCount < 2;
  const tooLong = wordCount > 12 || cleaned.length > 90;

  if (!cleaned || tooShort || tooLong || hasAmountNoise || hasPaymentNoise || hasVerbNoise || looksLikeRaw) {
    if (opts.merchant) {
      return opts.language === "es"
        ? `${opts.category} en ${opts.merchant}`
        : `${opts.category} at ${opts.merchant}`;
    }
    return `${opts.category} expense`;
  }

  return cleaned.slice(0, 90).trim();
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

function buildPaymentMethodNoiseTokens(ctx: ParserPaymentMethodContext): Set<string> {
  const defaults = [
    "card",
    "tarjeta",
    "amex",
    "visa",
    "mastercard",
    "master card",
    "debit",
    "credito",
    "crédito",
    "credit",
    "wallet",
    "apple pay",
    "cash",
    "method",
    "metodo",
    "método",
  ];
  const out = new Set<string>(defaults.map((value) => value.toLowerCase()));
  for (const alias of ctx.aliasToMethodIDs.keys()) {
    const normalized = alias.trim().toLowerCase();
    if (!normalized) continue;
    out.add(normalized);
  }
  return out;
}

function sanitizeMerchantStrict(candidate: string | null | undefined, paymentMethodTokens: Set<string>): string | null {
  const normalized = normalizeMerchantName(candidate);
  if (!normalized) return null;
  const lower = normalized.toLowerCase();

  if (normalized.split(/\s+/).filter(Boolean).length > 4) return null;
  if (/\d{1,3}(?:[.,\s'’]\d{3})*(?:[.,]\d{1,2})?/.test(normalized)) return null;
  if (/\b(peso|pesos|mxn|usd|eur|gbp|jpy|cad|brl|dollar|dollars|euro|euros)\b/i.test(normalized)) return null;
  if (/\b(me gast[ée]|gast[ée]|gaste|pagu[ée]|pague|compr[ée]|compre|spent|paid|bought)\b/i.test(normalized)) return null;
  if (containsAnyPhrase(lower, paymentMethodTokens)) return null;

  return normalized;
}

function containsAnyPhrase(value: string, phrases: Set<string>): boolean {
  for (const phrase of phrases) {
    if (!phrase) continue;
    const isWordPhrase = /^[a-z0-9áéíóúüñ ]+$/i.test(phrase);
    if (isWordPhrase) {
      if (new RegExp(`\\b${escapeRegex(phrase)}\\b`, "i").test(value)) {
        return true;
      }
      continue;
    }
    if (value.includes(phrase)) return true;
  }
  return false;
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

type AuthResolution = {
  user: { id: string } | null;
  strategy: string | null;
  error: string | null;
  attempts: AuthAttempt[];
};

type AuthAttempt = {
  strategy: string;
  ok: boolean;
  detail: string;
};

async function validateUserFromBearerToken(opts: {
  supabaseUrl: string;
  supabaseAnonKey: string;
  adminClient: ReturnType<typeof createClient>;
  bearerToken: string;
}): Promise<AuthResolution> {
  const { supabaseUrl, supabaseAnonKey, adminClient, bearerToken } = opts;
  const errors: string[] = [];
  const attempts: AuthAttempt[] = [];

  // Strategy 1: validate via service-role client.
  try {
    const { data, error } = await adminClient.auth.getUser(bearerToken);
    if (!error && data.user?.id) {
      attempts.push({ strategy: PRIMARY_AUTH_STRATEGY, ok: true, detail: "user resolved" });
      return { user: { id: data.user.id }, strategy: PRIMARY_AUTH_STRATEGY, error: null, attempts };
    }
    const detail = error?.message ? `adminClient: ${error.message}` : "adminClient: user not found";
    errors.push(detail);
    attempts.push({ strategy: PRIMARY_AUTH_STRATEGY, ok: false, detail });
  } catch (error) {
    const detail = `adminClient: ${String(error)}`;
    errors.push(detail);
    attempts.push({ strategy: PRIMARY_AUTH_STRATEGY, ok: false, detail });
  }

  // Strategy 2: validate via anon client.
  try {
    const anonClient = createClient(supabaseUrl, supabaseAnonKey);
    const { data, error } = await anonClient.auth.getUser(bearerToken);
    if (!error && data.user?.id) {
      const strategy = "anonClient.auth.getUser";
      attempts.push({ strategy, ok: true, detail: "user resolved" });
      return { user: { id: data.user.id }, strategy, error: null, attempts };
    }
    const detail = error?.message ? `anonClient: ${error.message}` : "anonClient: user not found";
    errors.push(detail);
    attempts.push({ strategy: "anonClient.auth.getUser", ok: false, detail });
  } catch (error) {
    const detail = `anonClient: ${String(error)}`;
    errors.push(detail);
    attempts.push({ strategy: "anonClient.auth.getUser", ok: false, detail });
  }

  // Strategy 3: direct REST call to Auth API.
  try {
    const strategy = "fetch /auth/v1/user";
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${bearerToken}`,
      },
    });
    if (response.ok) {
      const payload = await response.json() as { id?: string };
      if (payload?.id) {
        attempts.push({ strategy, ok: true, detail: "user resolved" });
        return { user: { id: payload.id }, strategy, error: null, attempts };
      }
      const detail = "auth REST: user payload missing id";
      errors.push(detail);
      attempts.push({ strategy, ok: false, detail });
    } else {
      const body = await response.text();
      const detail = `auth REST ${response.status}: ${body || "Unauthorized"}`;
      errors.push(detail);
      attempts.push({ strategy, ok: false, detail });
    }
  } catch (error) {
    const detail = `auth REST: ${String(error)}`;
    errors.push(detail);
    attempts.push({ strategy: "fetch /auth/v1/user", ok: false, detail });
  }

  return {
    user: null,
    strategy: null,
    error: errors[0] ?? "Unauthorized",
    attempts,
  };
}

function summarizeAuthAttempts(attempts: AuthAttempt[]): string[] {
  return attempts.map((attempt) => `${attempt.strategy}:${attempt.ok ? "ok" : "failed"}`);
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
