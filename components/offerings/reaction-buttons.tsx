"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState, useTransition } from "react";
import { CheckCircle2, Heart, Sparkles, type LucideIcon } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { ReactionCounts, ReactionType } from "@/lib/types";

type Props = {
  offeringId: string;
  initialCounts: ReactionCounts;
  compact?: boolean;
};

const REACTIONS: Array<{
  type: ReactionType;
  label: string;
  activeLabel: string;
  countKey: keyof ReactionCounts;
  icon: LucideIcon;
}> = [
  {
    type: "bless",
    label: "Bless",
    activeLabel: "Blessed",
    countKey: "bless_count",
    icon: Sparkles,
  },
  {
    type: "inspired_me",
    label: "Inspired",
    activeLabel: "Inspired",
    countKey: "inspired_count",
    icon: Heart,
  },
  {
    type: "i_did_this_too",
    label: "Did too",
    activeLabel: "Did too",
    countKey: "carried_forward_count",
    icon: CheckCircle2,
  },
];

export function ReactionButtons({ offeringId, initialCounts, compact = false }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const [counts, setCounts] = useState<ReactionCounts>({
    bless_count: initialCounts.bless_count ?? 0,
    inspired_count: initialCounts.inspired_count ?? 0,
    carried_forward_count: initialCounts.carried_forward_count ?? 0,
  });
  const [active, setActive] = useState<Set<ReactionType>>(new Set());
  const [userId, setUserId] = useState<string | null>(null);
  const [authChecked, setAuthChecked] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [pendingType, setPendingType] = useState<ReactionType | null>(null);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    setCounts({
      bless_count: initialCounts.bless_count ?? 0,
      inspired_count: initialCounts.inspired_count ?? 0,
      carried_forward_count: initialCounts.carried_forward_count ?? 0,
    });
  }, [
    initialCounts.bless_count,
    initialCounts.inspired_count,
    initialCounts.carried_forward_count,
  ]);

  useEffect(() => {
    let mounted = true;

    async function loadUserReactions() {
      try {
        const supabase = createClient();
        const {
          data: { user },
        } = await supabase.auth.getUser();

        if (!mounted) return;
        setUserId(user?.id ?? null);

        if (!user) return;

        const { data, error } = await supabase
          .from("reactions")
          .select("reaction_type")
          .eq("offering_id", offeringId)
          .eq("user_id", user.id);

        if (!mounted) return;
        if (error) {
          console.error("Could not load reaction state", error);
          return;
        }

        type ReactionRow = {
          reaction_type: ReactionType | string | null;
        };

        const reactionRows = (data ?? []) as ReactionRow[];
        const validReactionTypes = reactionRows
          .map((row) => row.reaction_type)
          .filter(
            (value): value is ReactionType =>
              value === "bless" ||
              value === "inspired_me" ||
              value === "i_did_this_too",
          );

        setActive(new Set(validReactionTypes));
      } catch (error) {
        console.error("Reaction auth check failed", error);
      } finally {
        if (mounted) setAuthChecked(true);
      }
    }

    loadUserReactions();

    return () => {
      mounted = false;
    };
  }, [offeringId]);

  const total = useMemo(
    () => counts.bless_count + counts.inspired_count + counts.carried_forward_count,
    [counts],
  );

  async function toggleReaction(
    reactionType: ReactionType,
    countKey: keyof ReactionCounts,
  ) {
    setMessage(null);

    if (!authChecked || pendingType || isPending) return;

    if (!userId) {
      setMessage("Sign in to bless, mark inspired, or carry this deed forward.");
      return;
    }

    const previousActive = new Set(active);
    const previousCounts = { ...counts };
    const currentlyActive = previousActive.has(reactionType);
    const nextActive = new Set(previousActive);
    const nextCounts = { ...previousCounts };

    if (currentlyActive) {
      nextActive.delete(reactionType);
      nextCounts[countKey] = Math.max(0, nextCounts[countKey] - 1);
    } else {
      nextActive.add(reactionType);
      nextCounts[countKey] = nextCounts[countKey] + 1;
    }

    setActive(nextActive);
    setCounts(nextCounts);
    setPendingType(reactionType);

    try {
      const supabase = createClient();
      const response = currentlyActive
        ? await supabase
            .from("reactions")
            .delete()
            .eq("offering_id", offeringId)
            .eq("user_id", userId)
            .eq("reaction_type", reactionType)
        : await supabase.from("reactions").insert({
            offering_id: offeringId,
            user_id: userId,
            reaction_type: reactionType,
          });

      if (response.error) {
        if (!currentlyActive && response.error.code === "23505") {
          setActive((current) => new Set([...Array.from(current), reactionType]));
          setCounts(previousCounts);
          startTransition(() => router.refresh());
          return;
        }

        throw response.error;
      }

      startTransition(() => router.refresh());
    } catch (error) {
      console.error("Reaction update failed", error);
      setActive(previousActive);
      setCounts(previousCounts);
      setMessage("Sorry, this reaction could not be saved. Please try again.");
    } finally {
      setPendingType(null);
    }
  }

  const loginHref = `/login?next=${encodeURIComponent(pathname || `/offerings/${offeringId}`)}`;

  return (
    <div className={compact ? "mt-4" : "mt-6"}>
      <div className={compact ? "grid grid-cols-3 gap-2 text-xs" : "grid gap-3 sm:grid-cols-3"}>
        {REACTIONS.map((reaction) => {
          const Icon = reaction.icon;
          const isActive = active.has(reaction.type);
          const isBusy = pendingType === reaction.type;
          const disabled = !authChecked || Boolean(pendingType) || isPending;

          return (
            <button
              key={reaction.type}
              type="button"
              disabled={disabled}
              onClick={() => toggleReaction(reaction.type, reaction.countKey)}
              className={[
                "focus-ring flex items-center justify-center gap-2 rounded-full border px-3 py-2 font-extrabold transition active:scale-[0.98]",
                compact ? "text-xs" : "text-sm sm:text-base",
                isActive
                  ? "border-[rgba(217,164,65,0.45)] bg-[#D9A441] text-[#26231F] shadow-[0_12px_28px_rgba(217,164,65,0.22)]"
                  : "border-[rgba(217,164,65,0.25)] bg-white/80 text-[#5F5548] hover:bg-[#FFF4DC]",
                disabled ? "cursor-wait opacity-70" : "",
              ].join(" ")}
              aria-pressed={isActive}
              aria-busy={isBusy}
            >
              <Icon className="h-4 w-4" />
              <span>{isBusy ? "Saving…" : isActive ? reaction.activeLabel : reaction.label}</span>
              <span className={isActive ? "text-[#26231F]/70" : "text-[#8D7C66]"}>
                {counts[reaction.countKey]}
              </span>
            </button>
          );
        })}
      </div>

      {message ? (
        <p
          aria-live="polite"
          className="mt-3 rounded-2xl bg-[#FFF4DC] px-4 py-3 text-sm font-bold leading-6 text-[#8D451D]"
        >
          {message}{" "}
          {!userId ? (
            <Link href={loginHref} className="underline">
              Sign in
            </Link>
          ) : null}
        </p>
      ) : null}

      {!compact && total > 0 ? (
        <p className="mt-3 text-center text-sm font-bold text-[#7C715F]">
          {total} total light actions recorded for this Offering.
        </p>
      ) : null}
    </div>
  );
}
