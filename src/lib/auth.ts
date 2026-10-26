import { supabase } from "@/integrations/supabase/client";

export type AppRole = "admin" | "manager" | "collaborateur";

/** Returns the signed-in user's whitelist role, or null if not whitelisted. RLS only exposes the user's own row. */
export async function fetchOwnRole(email: string): Promise<AppRole | null> {
  const { data: allowedUser, error: userError } = await supabase
    .from("allowed_users")
    .select("id")
    .eq("email", email.toLowerCase())
    .maybeSingle();
  if (userError) throw userError;
  if (!allowedUser) return null;

  const { data: roleRow, error: roleError } = await supabase
    .from("allowed_user_roles")
    .select("role")
    .eq("allowed_user_id", allowedUser.id)
    .maybeSingle();
  if (roleError) throw roleError;
  return (roleRow?.role as AppRole | undefined) ?? null;
}

export async function signOut() {
  await supabase.auth.signOut();
  window.location.replace("/auth");
}
