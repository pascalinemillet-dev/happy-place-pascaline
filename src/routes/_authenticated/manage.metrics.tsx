import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  ConfirmDelete,
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  RowActions,
  TextInput,
} from "@/components/manage/crud-ui";
import { metricSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import { MetricHistory } from "@/components/manage/metric-history";
import {
  comparedText,
  createMetric,
  dateFr,
  deleteMetric,
  fetchMetrics,
  deltaText,
  formatMetricValue,
  periodText,
  updateMetricRow,
  TREND_LABELS,
  type Metric,
  type MetricInput,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/manage/metrics")({
  head: () => ({
    meta: [
      { title: "Gestion des indicateurs — Happy Place" },
      { name: "description", content: "Créez, modifiez et supprimez les indicateurs de Happy Place." },
      { property: "og:title", content: "Gestion des indicateurs — Happy Place" },
      { property: "og:description", content: "Gérez les indicateurs de performance dans Happy Place." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManageMetrics,
});

type FormState = {
  key: string;
  label: string;
  value: string;
  unit: string;
  comptage: boolean;
  period_start: string;
  period_end: string;
  afficher_dashboard: boolean;
  ordre_dashboard: string;
};

const empty: FormState = {
  key: "",
  label: "",
  value: "",
  unit: "",
  comptage: false,
  period_start: "",
  period_end: "",
  afficher_dashboard: false,
  ordre_dashboard: "99",
};

function ManageMetrics() {
  const qc = useQueryClient();
  const [form, setForm] = useState<FormState | null>(null);
  const [editing, setEditing] = useState<Metric | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [toDelete, setToDelete] = useState<Metric | null>(null);

  const list = useQuery({ queryKey: ["metrics"], queryFn: fetchMetrics, retry: false });
  const invalidate = () => qc.invalidateQueries({ queryKey: ["metrics"] });
  const onError = (e: unknown) => toast.error((e as Error).message);

  const save = useMutation({
    mutationFn: (input: MetricInput) =>
      editing ? updateMetricRow(editing.key, input) : createMetric(input),
    onSuccess: async () => {
      toast.success(editing ? "Indicateur modifié" : "Indicateur créé");
      close();
      await invalidate();
    },
    onError,
  });

  const remove = useMutation({
    mutationFn: (key: string) => deleteMetric(key),
    onSuccess: () => {
      toast.success("Indicateur supprimé");
      setToDelete(null);
      invalidate();
    },
    onError,
  });

  function close() {
    setForm(null);
    setEditing(null);
    setErrors({});
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    const raw = form.value.trim().replace(",", ".");
    const candidate = {
      key: form.key,
      label: form.label,
      value: raw === "" || Number.isNaN(Number(raw)) ? Number.NaN : Number(raw),
      unit: form.unit.trim() === "" ? null : form.unit,
      comptage: form.comptage,
      period_start: form.period_start,
      period_end: form.period_end,
      afficher_dashboard: form.afficher_dashboard,
      ordre_dashboard: Number(form.ordre_dashboard),
    };
    const res = validate(metricSchema, candidate);
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  return (
    <section className="space-y-md">
      <div className="flex items-center justify-between">
        <h2 className="font-headline-sm text-headline-sm text-primary">
          Indicateurs ({list.data?.length ?? 0})
        </h2>
        <button
          onClick={() => {
            setEditing(null);
            setErrors({});
            setForm({ ...empty });
          }}
          className="px-md py-xs bg-primary text-on-primary font-label-md text-label-md"
        >
          + NOUVEL INDICATEUR
        </button>
      </div>

      {list.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
      {list.isError && (
        <p className="text-body-sm text-error">Impossible de charger les indicateurs.</p>
      )}

      <div className="space-y-xs">
        {list.data?.map((m) => (
          <article
            key={m.key}
            className="flex items-start justify-between gap-sm p-sm bg-card border border-outline-variant"
          >
            <div className="min-w-0 [overflow-wrap:anywhere]">
              <p className="font-body-md text-primary font-bold">
                {m.label} — {formatMetricValue(m.value, m.unit, m.comptage)}
              </p>
              <p className="text-[11px] font-label-sm text-on-surface-variant mt-xs">
                Période : {periodText(m.period_start, m.period_end)} · Mis à jour le{" "}
                {dateFr(m.updated_at)}
                {m.afficher_dashboard
                  ? ` · Sur le dashboard (n° ${m.ordre_dashboard})`
                  : " · Absent du dashboard"}
              </p>
              <p className="text-[11px] font-label-sm text-on-surface-variant">
                {m.key} • {TREND_LABELS[m.trend]}
                {m.previous_value != null && (
                  <>
                    {deltaText(m) && ` · ${deltaText(m)}`}
                    {` · avant : ${formatMetricValue(m.previous_value, m.unit, m.comptage).replace(/%$/, " %")}`}
                    {comparedText(m) && ` (${comparedText(m).replace("par rapport à la ", "")})`}
                  </>
                )}
              </p>
              <MetricHistory metricKey={m.key} unit={m.unit} comptage={m.comptage} />
            </div>
            <RowActions
              onEdit={() => {
                setEditing(m);
                setErrors({});
                setForm({
                  key: m.key,
                  label: m.label,
                  value: String(m.value),
                  unit: m.unit ?? "",
                  comptage: m.comptage,
                  period_start: m.period_start ?? "",
                  period_end: m.period_end ?? "",
                  afficher_dashboard: m.afficher_dashboard,
                  ordre_dashboard: String(m.ordre_dashboard),
                });
              }}
              onDelete={() => setToDelete(m)}
            />
          </article>
        ))}
        {list.data?.length === 0 && (
          <p className="text-body-sm italic text-on-surface-variant">Aucun indicateur.</p>
        )}
      </div>

      {form && (
        <Modal title={editing ? "Modifier l'indicateur" : "Nouvel indicateur"} onClose={close}>
          <form onSubmit={submit} className="space-y-sm" noValidate>
            <ErrorSummary errors={errors} />
            <Field label="Clé technique" error={errors.key}>
              <TextInput
                value={form.key}
                disabled={!!editing}
                maxLength={40}
                placeholder="ex : taux_placement"
                onChange={(e) => setForm({ ...form, key: e.target.value })}
              />
            </Field>
            <Field label="Libellé" error={errors.label}>
              <TextInput
                value={form.label}
                maxLength={60}
                onChange={(e) => setForm({ ...form, label: e.target.value })}
              />
            </Field>
            <Field label="Valeur" error={errors.value}>
              <TextInput
                value={form.value}
                inputMode="decimal"
                onChange={(e) => setForm({ ...form, value: e.target.value })}
              />
            </Field>
            <Field label="Unité (optionnel)" error={errors.unit}>
              <TextInput
                value={form.unit}
                maxLength={8}
                placeholder="%"
                onChange={(e) => setForm({ ...form, unit: e.target.value })}
              />
            </Field>
            <label className="flex items-center gap-xs text-body-sm text-primary">
              <input
                type="checkbox"
                checked={form.comptage}
                onChange={(e) => setForm({ ...form, comptage: e.target.checked })}
              />
              Comptage (nombre entier, sans décimale)
            </label>
            <div className="grid grid-cols-2 gap-sm">
              <Field label="Période : début" error={errors.period_start}>
                <TextInput
                  type="date"
                  required
                  value={form.period_start}
                  onChange={(e) => setForm({ ...form, period_start: e.target.value })}
                />
              </Field>
              <Field label="Période : fin" error={errors.period_end}>
                <TextInput
                  type="date"
                  required
                  value={form.period_end}
                  onChange={(e) => setForm({ ...form, period_end: e.target.value })}
                />
              </Field>
            </div>
            <p className="text-[11px] text-on-surface-variant">
              La période de calcul est obligatoire : elle s'affiche sur la carte de l'indicateur.
            </p>
            <div className="grid grid-cols-2 gap-sm items-end">
              <label className="flex items-center gap-xs text-body-sm text-primary pb-sm">
                <input
                  type="checkbox"
                  checked={form.afficher_dashboard}
                  onChange={(e) => setForm({ ...form, afficher_dashboard: e.target.checked })}
                />
                Afficher sur le dashboard
              </label>
              <Field label="Ordre sur le dashboard (1 à 99)" error={errors.ordre_dashboard}>
                <TextInput
                  type="number"
                  min={1}
                  max={99}
                  step={1}
                  value={form.ordre_dashboard}
                  disabled={!form.afficher_dashboard}
                  onChange={(e) => setForm({ ...form, ordre_dashboard: e.target.value })}
                />
              </Field>
            </div>
            <FormActions pending={save.isPending} onCancel={close} />
          </form>
        </Modal>
      )}

      {toDelete && (
        <ConfirmDelete
          label={toDelete.label}
          pending={remove.isPending}
          onCancel={() => setToDelete(null)}
          onConfirm={() => remove.mutate(toDelete.key)}
        />
      )}
    </section>
  );
}
