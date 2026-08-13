import { SignupForm } from "./signup-form";
import {
  isInvitationCodeActive,
  normalizeInvitationCode,
} from "@/lib/data/invitations";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<
  Record<string, string | string[] | undefined>
>;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function SignupPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const rawInvite = firstValue(params.invite);
  const normalizedInvite = normalizeInvitationCode(rawInvite);

  const invitationValid = normalizedInvite
    ? await isInvitationCodeActive(normalizedInvite)
    : false;

  const invitationState = rawInvite
    ? invitationValid
      ? "valid"
      : "invalid"
    : "none";

  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <SignupForm
        inviteCode={invitationValid ? normalizedInvite : null}
        invitationState={invitationState}
      />
    </section>
  );
}
