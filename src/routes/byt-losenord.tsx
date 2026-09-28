import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/byt-losenord")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Byt lösenord – Kompetensarena Norrbotten" },
      { name: "description", content: "Byt lösenord för ditt konto." },
      { property: "og:title", content: "Byt lösenord – Kompetensarena Norrbotten" },
      { property: "og:description", content: "Byt lösenord för ditt konto." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: ChangePasswordPage,
});

const btn =
  "inline-flex w-full items-center justify-center rounded-md border px-4 py-2.5 font-semibold transition-colors focus-visible:outline-2 disabled:opacity-60";

function ChangePasswordPage() {
  const navigate = useNavigate();
  const [current, setCurrent] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) navigate({ to: "/auth", replace: true });
      else setChecked(true);
    });
  }, [navigate]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setError("Lösenorden stämmer inte överens.");
      return;
    }
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.updateUser({ password, current_password: current });
    setBusy(false);
    if (error) {
      setError("Kunde inte byta lösenord. Kontrollera att det nuvarande lösenordet är rätt.");
    } else {
      setDone(true);
    }
  }

  if (!checked) return null;

  return (
    <Section className="py-10 md:py-14">
      <PageHeader eyebrow="Konto" title="Byt lösenord" intro="Ange ditt nuvarande lösenord och välj ett nytt." />
      <div className="mt-8 max-w-sm">
        {done ? (
          <p role="status" className="text-sm text-ink-muted">Lösenordet är bytt. Du är fortfarande inloggad.</p>
        ) : (
          <form onSubmit={onSubmit} className="space-y-3">
            <label className="block text-sm font-semibold">
              Nuvarande lösenord
              <input type="password" required autoComplete="current-password" value={current}
                onChange={(e) => setCurrent(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <label className="block text-sm font-semibold">
              Nytt lösenord
              <input type="password" required minLength={8} autoComplete="new-password" value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <label className="block text-sm font-semibold">
              Upprepa nytt lösenord
              <input type="password" required minLength={8} autoComplete="new-password" value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <button type="submit" disabled={busy} className={`${btn} border-brand-dark bg-brand-dark text-primary-foreground hover:opacity-90`}>
              {busy ? "Sparar…" : "Byt lösenord"}
            </button>
          </form>
        )}
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </div>
    </Section>
  );
}
