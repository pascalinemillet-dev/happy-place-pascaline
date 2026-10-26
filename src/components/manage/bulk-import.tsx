import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { loadBrowserLib } from "@/lib/browser-lib";

type ImportRow = { line: number; last_name: string; first_name: string; email: string; role: string; team: string };
type ResultRow = {
  line: number; email: string; last_name: string | null; first_name: string | null;
  role: string; team: string | null; status: "valide" | "importée" | "refusée"; reason: string | null;
};
type Result = { dry_run: boolean; accepted: number; rejected: number; rows: ResultRow[] };

const norm = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
const HEADERS: Record<string, keyof Omit<ImportRow, "line">> = {
  nom: "last_name", prenom: "first_name", "adresse mail": "email", email: "email", role: "role", equipe: "team",
};

function parseCsv(text: string): string[][] {
  text = text.replace(/^\uFEFF/, "");
  const firstLine = text.split(/\r?\n/)[0] ?? "";
  const sep = (firstLine.match(/;/g)?.length ?? 0) > (firstLine.match(/,/g)?.length ?? 0) ? ";" : ",";
  const rows: string[][] = [];
  let row: string[] = [], cell = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; }
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === sep) { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); rows.push(row); row = []; cell = "";
    } else cell += c;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function download(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

const FALLBACK_TEAMS = [
  "Accounting", "Direction Commerciale", "Direction Conseil", "Direction recrutement", "Finance", "Legal",
  "Marketing", "Opérations", "People", "Pôle Data et IA", "Product", "Relation clients", "Admin",
];

async function fetchTeams(): Promise<string[]> {
  try {
    const { data, error } = await supabase.from("teams").select("name");
    if (error) throw error;
    const names = (data ?? []).map((r) => r.name);
    const others = names.filter((n) => norm(n) !== "admin").sort((a, b) => a.localeCompare(b, "fr", { sensitivity: "base" }));
    const admin = names.find((n) => norm(n) === "admin") ?? "Admin";
    return [...others, admin];
  } catch {
    return FALLBACK_TEAMS;
  }
}

async function downloadTemplate() {
  const ExcelJS = await loadBrowserLib<typeof import("exceljs")>("/vendor/exceljs-4.4.0.min.js", "ExcelJS");
  const teams = await fetchTeams();
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Utilisateurs", { views: [{ state: "frozen", ySplit: 1 }] });
  ws.columns = [
    { header: "Nom", width: 20 }, { header: "Prénom", width: 20 }, { header: "Adresse mail", width: 34 },
    { header: "Rôle", width: 18 }, { header: "Équipe", width: 20 },
  ];
  ws.getRow(1).font = { bold: true };
  const teamRange = `Listes!$B$2:$B$${teams.length + 1}`;
  for (let r = 2; r <= 501; r++) {
    ws.getCell(`D${r}`).dataValidation = {
      type: "list", allowBlank: true, formulae: ["Listes!$A$2:$A$4"],
      showErrorMessage: true, errorTitle: "Valeur invalide", error: "Choisis un rôle dans la liste.",
    };
    ws.getCell(`E${r}`).dataValidation = {
      type: "list", allowBlank: true, formulae: [teamRange],
      showErrorMessage: true, errorTitle: "Valeur invalide", error: "Choisis une équipe dans la liste.",
    };
  }
  const lists = wb.addWorksheet("Listes");
  const roles = ["Rôles", "admin", "manager", "collaborateur"];
  const teamCol = ["Équipes", ...teams];
  roles.forEach((v, i) => (lists.getCell(`A${i + 1}`).value = v));
  teamCol.forEach((v, i) => (lists.getCell(`B${i + 1}`).value = v));
  lists.getRow(1).font = { bold: true };
  const help = wb.addWorksheet("Mode d'emploi");
  help.getColumn(1).width = 110;
  [
    "1. Ouvre ce fichier dans Google Sheets (Fichier > Importer) ou Excel.",
    "2. Remplis une ligne par personne dans l'onglet Utilisateurs.",
    "3. Choisis le rôle et l'équipe dans les menus déroulants.",
    "4. Une adresse mail ne peut apparaître qu'une fois : une adresse = un rôle.",
    "5. Collaborateur : équipe obligatoire. Manager : équipe facultative, une équipe peut avoir plusieurs managers. Admin : équipe vide ou Admin.",
    "6. Exporte l'onglet Utilisateurs en CSV (Google Sheets : Fichier > Télécharger > CSV).",
    "7. Dans Happy Place : Gérer > Utilisateurs autorisés > Importer une liste, vérifie l'aperçu puis confirme.",
    "8. L'équipe doit exister dans Happy Place : un admin peut en créer une dans Gérer > Utilisateurs autorisés > Équipes.",
  ].forEach((t, i) => (help.getCell(`A${i + 1}`).value = t));
  const buf = await wb.xlsx.writeBuffer();
  download(new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), "happy-place-import-utilisateurs.xlsx");
}

function downloadReport(rows: ResultRow[]) {
  const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
  const lines = [["Ligne", "Nom", "Prénom", "Adresse mail", "Rôle", "Équipe", "Statut", "Motif"].map(esc).join(";")];
  rows.forEach((r) => lines.push([r.line, r.last_name, r.first_name, r.email, r.role, r.team, r.status, r.reason].map(esc).join(";")));
  download(new Blob(["\uFEFF" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" }), "happy-place-rapport-import.csv");
}

export function BulkImport({ onImported }: { onImported: () => void }) {
  const [sent, setSent] = useState<ImportRow[]>([]);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [inputKey, setInputKey] = useState(0);

  async function onFile(file: File | undefined) {
    setError(null); setResult(null);
    if (!file) return;
    if (!file.name.toLowerCase().endsWith(".csv")) return setError("Seuls les fichiers .csv sont acceptés.");
    if (file.size > 1024 * 1024) return setError("Fichier trop volumineux (1 Mo maximum).");
    const table = parseCsv(await file.text());
    const header = (table[0] ?? []).map((h) => HEADERS[norm(h)]);
    const missing = [["last_name", "Nom"], ["first_name", "Prénom"], ["email", "Adresse mail"], ["role", "Rôle"]]
      .filter(([k]) => !header.includes(k as never)).map(([, l]) => l);
    if (missing.length) return setError(`Colonne(s) obligatoire(s) manquante(s) : ${missing.join(", ")}.`);
    const rows: ImportRow[] = [];
    table.slice(1).forEach((cells, idx) => {
      if (cells.every((c) => c.trim() === "")) return;
      const r: ImportRow = { line: idx + 2, last_name: "", first_name: "", email: "", role: "", team: "" };
      header.forEach((k, i) => { if (k) r[k] = (cells[i] ?? "").trim(); });
      rows.push(r);
    });
    if (!rows.length) return setError("Le fichier ne contient aucune ligne.");
    setBusy(true);
    const { data, error: e } = await supabase.rpc("bulk_import_allowed_users", { _rows: rows, _dry_run: true });
    setBusy(false);
    if (e) return setError(e.message);
    setSent(rows); setResult(data as unknown as Result);
  }

  async function confirmImport() {
    if (!result) return;
    const validLines = new Set(result.rows.filter((r) => r.status === "valide").map((r) => r.line));
    if (!confirm(`Importer ${validLines.size} utilisateur(s) ?`)) return;
    const toSend = sent.filter((r) => validLines.has(r.line));
    setBusy(true);
    const { data, error: e } = await supabase.rpc("bulk_import_allowed_users", { _rows: toSend, _dry_run: false });
    setBusy(false);
    if (e) return toast.error(e.message);
    const res = data as unknown as Result;
    const imported = new Map(res.rows.map((r) => [r.line, r]));
    const merged = result.rows.map((r) => imported.get(r.line) ?? r);
    const rejected = merged.filter((r) => r.status === "refusée").length;
    toast.success(`${res.accepted} utilisateurs importés, ${rejected} lignes refusées`);
    setResult({ dry_run: false, accepted: res.accepted, rejected, rows: merged });
    onImported();
  }

  function cancel() { setResult(null); setSent([]); setError(null); setInputKey((k) => k + 1); }

  const btn = "px-md py-xs border border-outline text-primary font-label-md text-label-md hover:bg-surface-container disabled:opacity-50";
  const validCount = result?.rows.filter((r) => r.status === "valide").length ?? 0;

  return (
    <section className="space-y-sm bg-surface-container-lowest border border-outline-variant p-md">
      <h2 className="font-label-md text-label-md text-primary">Importer une liste</h2>
      <div className="flex flex-wrap items-center gap-sm">
        <button type="button" className={btn} onClick={() => downloadTemplate().catch((e) => toast.error((e as Error).message))}>
          Télécharger le modèle (.xlsx)
        </button>
        <input
          key={inputKey}
          type="file"
          accept=".csv,text/csv"
          aria-label="Fichier CSV à importer"
          disabled={busy}
          onChange={(e) => onFile(e.target.files?.[0])}
          className="text-body-sm"
        />
        {busy && <span className="text-body-sm">…</span>}
      </div>
      {error && <p className="text-error text-sm">{error}</p>}
      {result && (
        <div className="space-y-sm">
          <p className="text-body-sm text-primary">
            {result.dry_run
              ? `${result.accepted} lignes valides · ${result.rejected} lignes refusées`
              : `${result.accepted} lignes importées · ${result.rejected} lignes refusées`}
          </p>
          <div className="flex flex-wrap gap-sm">
            {result.dry_run && (
              <button type="button" className="px-md py-xs bg-primary text-on-primary font-label-md text-label-md disabled:opacity-50" disabled={validCount === 0 || busy} onClick={confirmImport}>
                Importer les {validCount} lignes valides
              </button>
            )}
            <button type="button" className={btn} onClick={() => downloadReport(result.rows)}>Télécharger le rapport (CSV)</button>
            <button type="button" className={btn} onClick={cancel}>Annuler</button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-body-sm">
              <thead>
                <tr className="text-left border-b border-outline-variant">
                  {["Ligne", "Nom", "Prénom", "Adresse mail", "Rôle", "Équipe", "Statut", "Motif"].map((h) => <th key={h} className="p-xs">{h}</th>)}
                </tr>
              </thead>
              <tbody>
                {result.rows.map((r) => (
                  <tr key={r.line} className={`border-b border-outline-variant ${r.status === "refusée" ? "text-error" : ""}`}>
                    <td className="p-xs">{r.line}</td><td className="p-xs">{r.last_name}</td><td className="p-xs">{r.first_name}</td>
                    <td className="p-xs">{r.email}</td><td className="p-xs">{r.role}</td><td className="p-xs">{r.team}</td>
                    <td className="p-xs">{r.status}</td><td className="p-xs">{r.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
