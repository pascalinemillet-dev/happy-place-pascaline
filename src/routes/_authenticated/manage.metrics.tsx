import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import {
  ConfirmDelete,
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  RowActions,
  Select,
  TextInput,
} from "@/components/manage/crud-ui";
import { indicateurSchema, valeurMensuelleSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import { MetricHistory } from "@/components/manage/metric-history";
import {
  createIndicateur,
  deleteMetric,
  dernierMoisTermine,
  ecartFleche,
  ecartText,
  fetchClesRenseignees,
  fetchIndicateursDuMois,
  fetchValeursMensuelles,
  formatMetricValue,
  messageIndicateur,
  moisIso,
  moisText,
  MOIS_LABELS,
  saveValeurMensuelle,
  updateIndicateur,
  updateMoisReference,
  EVOLUTION_CLASSES,
  EVOLUTION_LABELS,
  type IndicateurInput,
  type IndicateurMois,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/manage/metrics")({
  head: () => ({
    meta: [
      { title: "Gestion des indicateurs — Happy Place" },
      { name: "description", content: "Choisissez le mois des indicateurs et saisissez leurs valeurs dans Happy Place." },
      { property: "og:title", content: "Gestion des indicateurs — Happy Place" },
      { property: "og:description", content: "Gérez les indicateurs de performance dans Happy Place." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManageMetrics,
});

type DefinitionForm = {
  key: string;
  label: string;
  unit: string;
  comptage: boolean;
  sens_favorable: "hausse" | "baisse";
  afficher_dashboard: boolean;
  ordre_dashboard: string;
};

const emptyDefinition: DefinitionForm = {
  key: "",
  label: "",
  unit: "",
  comptage: false,
  sens_favorable: "hausse",
  afficher_dashboard: false,
  ordre_dashboard: "99",
};

/** Années proposées : de 2024 à l'année du dernier mois terminé. */
function annees(dernierMois: string): number[] {
  const fin = Number(dernierMois.slice(0, 4));
  const out: number[] = [];
  for (let a = fin; a >= 2024; a--) out.push(a);
  return out;
}

/** Choix d'un mois et d'une année, limité aux mois terminés. */
function MoisAnnee({
  value,
  onChange,
  dernierMois,
  idPrefix,
}: {
  value: string;
  onChange: (iso: string) => void;
  dernierMois: string;
  idPrefix: string;
}) {
  const annee = Number(value.slice(0, 4));
  const mois = Number(value.slice(5, 7));
  const anneeMax = Number(dernierMois.slice(0, 4));
  const moisMax = Number(dernierMois.slice(5, 7));
  return (
    <div className="grid grid-cols-2 gap-sm">
      <Field label="Mois">
        <Select
          id={`${idPrefix}-mois`}
          aria-label="Mois"
          value={mois}
          onChange={(e) => onChange(moisIso(annee, Number(e.target.value)))}
        >
          {MOIS_LABELS.map((l, i) => (
            <option key={l} value={i + 1} disabled={annee === anneeMax && i + 1 > moisMax}>
              {l}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Année">
        <Select
          id={`${idPrefix}-annee`}
          aria-label="Année"
          value={annee}
          onChange={(e) => {
            const a = Number(e.target.value);
            onChange(moisIso(a, a === anneeMax ? Math.min(mois, moisMax) : mois));
          }}
        >
          {annees(dernierMois).map((a) => (
            <option key={a} value={a}>
              {a}
            </option>
          ))}
        </Select>
      </Field>
    </div>
  );
}

function ManageMetrics() {
  const qc = useQueryClient();
  const dernierMois = dernierMoisTermine();
  const [definition, setDefinition] = useState<DefinitionForm | null>(null);
  const [editing, setEditing] = useState<IndicateurMois | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [toDelete, setToDelete] = useState<IndicateurMois | null>(null);
  const [saisie, setSaisie] = useState<IndicateurMois | null>(null);

  const list = useQuery({ queryKey: ["metrics", "mois"], queryFn: fetchIndicateursDuMois, retry: false });
  const moisAffiche = list.data?.[0]?.mois ?? null;
  const invalidate = () => qc.invalidateQueries({ queryKey: ["metrics"] });
  const onError = (e: unknown) => toast.error(messageIndicateur(e));

  const save = useMutation({
    mutationFn: (input: IndicateurInput) =>
      editing ? updateIndicateur(editing.key, input) : createIndicateur(input),
    onSuccess: async () => {
      toast.success(editing ? "Indicateur modifié" : "Indicateur créé");
      closeDefinition();
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

  function closeDefinition() {
    setDefinition(null);
    setEditing(null);
    setErrors({});
  }

  function submitDefinition(e: React.FormEvent) {
    e.preventDefault();
    if (!definition) return;
    const candidate = {
      key: definition.key,
      label: definition.label,
      unit: definition.unit.trim() === "" ? null : definition.unit,
      comptage: definition.comptage,
      sens_favorable: definition.sens_favorable,
      afficher_dashboard: definition.afficher_dashboard,
      ordre_dashboard: Number(definition.ordre_dashboard),
    };
    const res = validate(indicateurSchema, candidate);
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  const affiches = (list.data ?? []).filter((m) => m.afficher_dashboard).map((m) => m.key);

  return (
    <section className="space-y-md">
      <MoisReference
        moisAffiche={moisAffiche}
        dernierMois={dernierMois}
        affiches={affiches}
        onSaved={invalidate}
      />

      <div className="flex items-center justify-between">
        <h2 className="font-headline-sm text-headline-sm text-primary">
          Indicateurs ({list.data?.length ?? 0})
        </h2>
        <button
          onClick={() => {
            setEditing(null);
            setErrors({});
            setDefinition({ ...emptyDefinition });
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
                {m.label} — {moisText(m.mois)} :{" "}
                {m.value != null ? formatMetricValue(m.value, m.unit, m.comptage) : "non renseigné"}
              </p>
              {m.value != null && m.evolution && (
                <p className={`text-[11px] font-label-sm font-bold ${EVOLUTION_CLASSES[m.evolution]}`}>
                  <span className="sr-only">Évolution {EVOLUTION_LABELS[m.evolution]} : </span>
                  {m.evolution === "nc"
                    ? `N.C. : pas de valeur pour ${moisText(m.mois_precedent)}`
                    : `${ecartFleche(m.ecart)} ${ecartText(m.ecart, m.unit, m.comptage)} vs ${moisText(m.mois_precedent)} (${formatMetricValue(m.valeur_precedente as number, m.unit, m.comptage)})`}
                </p>
              )}
              <p className="text-[11px] font-label-sm text-on-surface-variant mt-xs">
                {m.key} · Favorable à la {m.sens_favorable}
                {m.comptage && " · Comptage"}
                {m.afficher_dashboard
                  ? ` · Sur le dashboard (n° ${m.ordre_dashboard})`
                  : " · Absent du dashboard"}
              </p>
              <MetricHistory metricKey={m.key} unit={m.unit} comptage={m.comptage} />
            </div>
            <div className="flex flex-col items-end gap-xs shrink-0">
              <button
                type="button"
                onClick={() => setSaisie(m)}
                className="px-sm py-1 bg-primary text-on-primary font-label-sm text-label-sm"
              >
                SAISIR UNE VALEUR
              </button>
              <RowActions
                onEdit={() => {
                  setEditing(m);
                  setErrors({});
                  setDefinition({
                    key: m.key,
                    label: m.label,
                    unit: m.unit ?? "",
                    comptage: m.comptage,
                    sens_favorable: m.sens_favorable,
                    afficher_dashboard: m.afficher_dashboard,
                    ordre_dashboard: String(m.ordre_dashboard),
                  });
                }}
                onDelete={() => setToDelete(m)}
              />
            </div>
          </article>
        ))}
        {list.data?.length === 0 && (
          <p className="text-body-sm italic text-on-surface-variant">Aucun indicateur.</p>
        )}
      </div>

      {definition && (
        <Modal title={editing ? "Modifier l'indicateur" : "Nouvel indicateur"} onClose={closeDefinition}>
          <form onSubmit={submitDefinition} className="space-y-sm" noValidate>
            <ErrorSummary errors={errors} />
            <Field label="Clé technique" error={errors.key}>
              <TextInput
                value={definition.key}
                disabled={!!editing}
                maxLength={40}
                placeholder="ex : taux_placement"
                onChange={(e) => setDefinition({ ...definition, key: e.target.value })}
              />
            </Field>
            <Field label="Libellé" error={errors.label}>
              <TextInput
                value={definition.label}
                maxLength={60}
                onChange={(e) => setDefinition({ ...definition, label: e.target.value })}
              />
            </Field>
            <Field label="Unité (optionnel)" error={errors.unit}>
              <TextInput
                value={definition.unit}
                maxLength={8}
                placeholder="%"
                onChange={(e) => setDefinition({ ...definition, unit: e.target.value })}
              />
            </Field>
            <label className="flex items-center gap-xs text-body-sm text-primary">
              <input
                type="checkbox"
                checked={definition.comptage}
                onChange={(e) => setDefinition({ ...definition, comptage: e.target.checked })}
              />
              Comptage (nombre entier, sans décimale)
            </label>
            <Field label="Évolution favorable" error={errors.sens_favorable}>
              <Select
                value={definition.sens_favorable}
                onChange={(e) =>
                  setDefinition({ ...definition, sens_favorable: e.target.value as "hausse" | "baisse" })
                }
              >
                <option value="hausse">Une hausse est favorable (verte)</option>
                <option value="baisse">Une baisse est favorable (verte), ex. un délai</option>
              </Select>
            </Field>
            <div className="grid grid-cols-2 gap-sm items-end">
              <label className="flex items-center gap-xs text-body-sm text-primary pb-sm">
                <input
                  type="checkbox"
                  checked={definition.afficher_dashboard}
                  onChange={(e) => setDefinition({ ...definition, afficher_dashboard: e.target.checked })}
                />
                Afficher sur le dashboard
              </label>
              <Field label="Ordre sur le dashboard (1 à 99)" error={errors.ordre_dashboard}>
                <TextInput
                  type="number"
                  min={1}
                  max={99}
                  step={1}
                  value={definition.ordre_dashboard}
                  disabled={!definition.afficher_dashboard}
                  onChange={(e) => setDefinition({ ...definition, ordre_dashboard: e.target.value })}
                />
              </Field>
            </div>
            <p className="text-[11px] text-on-surface-variant">
              La valeur se saisit ensuite pour chaque mois, avec « Saisir une valeur ».
            </p>
            <FormActions pending={save.isPending} onCancel={closeDefinition} />
          </form>
        </Modal>
      )}

      {saisie && (
        <SaisieValeur
          indicateur={saisie}
          moisDefaut={dernierMois}
          dernierMois={dernierMois}
          onClose={() => setSaisie(null)}
          onSaved={invalidate}
        />
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

/** Mois affiché sur le dashboard, le même pour tous les indicateurs. */
function MoisReference({
  moisAffiche,
  dernierMois,
  affiches,
  onSaved,
}: {
  moisAffiche: string | null;
  dernierMois: string;
  affiches: string[];
  onSaved: () => Promise<void> | void;
}) {
  // Le sélecteur propose le dernier mois terminé.
  const [choix, setChoix] = useState(dernierMois);
  const renseignes = useQuery({
    queryKey: ["metrics", "renseignes", choix],
    queryFn: () => fetchClesRenseignees(choix),
  });

  const save = useMutation({
    mutationFn: () => updateMoisReference(choix),
    onSuccess: async () => {
      toast.success(`Le dashboard affiche ${moisText(choix)}`);
      await onSaved();
    },
    onError: (e) => toast.error(messageIndicateur(e)),
  });

  return (
    <div className="p-md bg-card border border-outline-variant space-y-sm">
      <div className="flex items-baseline justify-between gap-sm flex-wrap">
        <h2 className="font-headline-sm text-headline-sm text-primary">Mois des indicateurs</h2>
        <p className="text-body-sm text-on-surface-variant">
          Affiché sur le dashboard :{" "}
          <strong className="text-primary">{moisAffiche ? moisText(moisAffiche) : "…"}</strong>
        </p>
      </div>
      <p className="text-body-sm text-on-surface-variant">
        Tous les indicateurs portent sur le même mois terminé et se comparent au mois précédent.
        Saisissez d'abord les valeurs du mois, puis affichez-le.
      </p>
      <div className="flex items-end gap-sm flex-wrap">
        <div className="min-w-[260px]">
          <MoisAnnee value={choix} onChange={setChoix} dernierMois={dernierMois} idPrefix="mois-ref" />
        </div>
        <button
          type="button"
          disabled={save.isPending || choix === moisAffiche}
          onClick={() => save.mutate()}
          className="px-md py-sm bg-primary text-on-primary font-label-md text-label-md disabled:opacity-50"
        >
          {choix === moisAffiche ? "DÉJÀ AFFICHÉ" : `AFFICHER ${moisText(choix).toUpperCase()}`}
        </button>
      </div>
      {renseignes.data && (
        <p className="text-body-sm text-on-surface-variant" aria-live="polite">
          Indicateurs du dashboard renseignés pour {moisText(choix)} :{" "}
          <strong className="text-primary">
            {affiches.filter((k) => renseignes.data.includes(k)).length} sur {affiches.length}
          </strong>
        </p>
      )}
    </div>
  );
}

/** Saisie ou correction de la valeur d'un indicateur pour un mois terminé. */
function SaisieValeur({
  indicateur,
  moisDefaut,
  dernierMois,
  onClose,
  onSaved,
}: {
  indicateur: IndicateurMois;
  moisDefaut: string;
  dernierMois: string;
  onClose: () => void;
  onSaved: () => Promise<void> | void;
}) {
  const [mois, setMois] = useState(moisDefaut);
  const [valeur, setValeur] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const valeurs = useQuery({
    queryKey: ["metrics", "mensuels", indicateur.key],
    queryFn: () => fetchValeursMensuelles(indicateur.key),
  });
  const existante = useMemo(
    () => valeurs.data?.find((v) => v.mois === mois) ?? null,
    [valeurs.data, mois],
  );

  // Valeur déjà saisie pour ce mois : proposée pour correction.
  useEffect(() => {
    setValeur(existante ? String(existante.value).replace(".", ",") : "");
  }, [existante]);

  const save = useMutation({
    mutationFn: (input: { mois: string; value: number }) =>
      saveValeurMensuelle({ metric_key: indicateur.key, ...input }),
    onSuccess: async () => {
      toast.success(`${indicateur.label} : ${moisText(mois)} enregistré`);
      onClose();
      await onSaved();
    },
    onError: (e) => toast.error(messageIndicateur(e)),
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const raw = valeur.trim().replace(",", ".");
    const res = validate(valeurMensuelleSchema(indicateur.comptage, dernierMois), {
      mois,
      value: raw === "" || Number.isNaN(Number(raw)) ? Number.NaN : Number(raw),
    });
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  return (
    <Modal title={`Saisir : ${indicateur.label}`} onClose={onClose}>
      <form onSubmit={submit} className="space-y-sm" noValidate>
        <ErrorSummary errors={errors} />
        <MoisAnnee value={mois} onChange={setMois} dernierMois={dernierMois} idPrefix="saisie" />
        <Field
          label={`Valeur pour ${moisText(mois)}${indicateur.unit ? ` (${indicateur.unit.trim()})` : ""}`}
          error={errors.value}
        >
          <TextInput
            value={valeur}
            inputMode={indicateur.comptage ? "numeric" : "decimal"}
            onChange={(e) => setValeur(e.target.value)}
          />
        </Field>
        <p className="text-[11px] text-on-surface-variant">
          {existante
            ? `Une valeur existe déjà pour ${moisText(mois)} : elle sera remplacée.`
            : `Aucune valeur pour ${moisText(mois)}.`}
          {indicateur.comptage && " Comptage : nombre entier."}
        </p>
        <FormActions pending={save.isPending} onCancel={onClose} />
      </form>
    </Modal>
  );
}
