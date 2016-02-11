Require Import String List Program.Equality.
Require Import Lib.CommonTactics Lib.FMap Lib.Struct.
Require Import Syntax Semantics.

Set Implicit Arguments.

Theorem staticDynCallsRules m o name a u cs r:
  In (name :: a)%struct (getRules m) ->
  SemAction o (a type) u cs r ->
  forall f, M.In f cs -> In f (getCalls m).
Proof.
  admit.
Qed.

Theorem staticDynCallsMeths m o name a u cs r:
  In (name :: a)%struct (getDefsBodies m) ->
  forall argument,
    SemAction o (projT2 a type argument) u cs r ->
    forall f, M.In f cs -> In f (getCalls m).
Proof.
  admit.
Qed.

Theorem staticDynCallsSubstep m o u rm cs:
  Substep m o u rm cs ->
  forall f, M.In f cs -> In f (getCalls m).
Proof.
  intro H.
  dependent induction H; simpl in *; intros.
  - apply (M.F.P.F.empty_in_iff) in H; intuition.
  - apply (M.F.P.F.empty_in_iff) in H; intuition.
  - eapply staticDynCallsRules; eauto.
  - destruct f as [name a]; simpl in *.
    eapply staticDynCallsMeths; eauto.
Qed.

Theorem staticDynDefsSubstep m o u far cs:
  Substep m o u (Meth (Some far)) cs ->
  List.In (attrName far) (getDefs m).
Proof.
  intros.
  dependent induction H; simpl in *.
  unfold getDefs in *.
  clear - HIn.
  induction (getDefsBodies m).
  - intuition.
  - simpl in *.
    destruct HIn.
    + subst.
      left; intuition.
    + right; intuition.
Qed.

Theorem staticDynCallsSubsteps m o ss:
  forall f, M.In f (calls (foldSSLabel (m := m) (o := o) ss)) -> In f (getCalls m).
Proof.
  intros.
  induction ss; simpl in *.
  - exfalso.
    apply (proj1 (M.F.P.F.empty_in_iff _ _) H).
  - unfold addLabelLeft, mergeLabel in *.
    destruct a.
    simpl in *.
    destruct unitAnnot.
    + destruct (foldSSLabel ss); simpl in *.
      pose proof (M.union_In H) as sth.
      destruct sth.
      * apply (staticDynCallsSubstep substep); intuition.
      * intuition.
    + destruct (foldSSLabel ss); simpl in *.
      dependent destruction o0; simpl in *.
      * dependent destruction a; simpl in *.
        pose proof (M.union_In H) as sth.
        { destruct sth.
          - apply (staticDynCallsSubstep substep); intuition.
          - intuition.
        }
      * pose proof (M.union_In H) as sth.
        { destruct sth.
          - apply (staticDynCallsSubstep substep); intuition.
          - intuition.
        }
Qed.

Theorem staticDynDefsSubsteps m o ss:
  forall f, M.In f (defs (foldSSLabel (m := m) (o := o) ss)) -> In f (getDefs m).
Proof.
  intros.
  induction ss; simpl in *.
  - exfalso.
    apply (proj1 (M.F.P.F.empty_in_iff _ _) H).
  - unfold addLabelLeft, mergeLabel in *.
    destruct a.
    simpl in *.
    destruct unitAnnot.
    + destruct (foldSSLabel ss); simpl in *.
      rewrite M.union_empty_L in H.
      intuition.
    + destruct (foldSSLabel ss); simpl in *.
      dependent destruction o0; simpl in *.
      * dependent destruction a; simpl in *.
        pose proof (M.union_In H) as sth.
        { destruct sth.
          - apply M.F.P.F.add_in_iff in H0.
            destruct H0.
            + subst.
              apply (staticDynDefsSubstep substep).
            + exfalso; apply ((proj1 (M.F.P.F.empty_in_iff _ _)) H0).
          - intuition.
        }
      * rewrite M.union_empty_L in H.
        intuition.
Qed.

Lemma hide_idempotent:
  forall (l: LabelT), hide l = hide (hide l).
Proof.
  intros; destruct l as [ann ds cs].
  unfold hide; simpl; f_equal;
  apply M.subtractKV_idempotent.
Qed.

Lemma filterDms_getCalls:
  forall regs rules dms filt,
    SubList (getCalls (Mod regs rules (filterDms dms filt)))
            (getCalls (Mod regs rules dms)).
Proof.
  unfold getCalls; simpl; intros.
  apply SubList_app_3; [apply SubList_app_1, SubList_refl|].
  apply SubList_app_2.

  clear.
  induction dms; simpl; [apply SubList_nil|].
  destruct (in_dec _ _ _).
  - apply SubList_app_2; auto.
  - apply SubList_app_3.
    + apply SubList_app_1, SubList_refl.
    + apply SubList_app_2; auto.
Qed.

Lemma filterDms_wellHidden:
  forall regs rules dms l,
    wellHidden (Mod regs rules dms) (hide l) ->
    forall filt,
      wellHidden (Mod regs rules (filterDms dms filt)) (hide l).
Proof.
  unfold wellHidden, hide; simpl; intros; dest.
  split.
  - eapply M.KeysDisj_SubList; eauto.
    apply filterDms_getCalls.
  - unfold getDefs in *; simpl in *.
    eapply M.KeysDisj_SubList; eauto.

    clear.
    induction dms; simpl; auto.
    + apply SubList_nil.
    + destruct (in_dec _ _ _).
      * apply SubList_cons_right; auto.
      * simpl; apply SubList_cons; auto.
        apply SubList_cons_right; auto.
Qed.

Lemma merge_preserves_substep:
  forall m or u ul cs,
    Substep m or u ul cs ->
    Substep (Mod (getRegInits m) (getRules m) (getDefsBodies m)) or u ul cs.
Proof. induction 1; simpl; intros; try (econstructor; eauto). Qed.

Lemma merge_preserves_substepsInd:
  forall m or u l,
    SubstepsInd m or u l ->
    SubstepsInd (Mod (getRegInits m) (getRules m) (getDefsBodies m)) or u l.
Proof.
  induction 1; intros; [constructor|].
  subst; eapply SubstepsCons; eauto.
  apply merge_preserves_substep; auto.
Qed.

Lemma merge_preserves_stepInd:
  forall m or nr l,
    StepInd m or nr l ->
    StepInd (Mod (getRegInits m) (getRules m) (getDefsBodies m)) or nr l.
Proof.
  intros; inv H.
  constructor; auto.
  apply merge_preserves_substepsInd; auto.
Qed.

Lemma merge_preserves_step:
  forall m or nr l,
    Step m or nr l ->
    Step (Mod (getRegInits m) (getRules m) (getDefsBodies m)) or nr l.
Proof.
  intros; apply step_consistent; apply step_consistent in H.
  apply merge_preserves_stepInd; auto.
Qed.

Lemma substepInd_dms_weakening:
  forall regs rules dms or u l,
    DisjList (getCalls (Mod regs rules dms)) (getDefs (Mod regs rules dms)) ->
    SubstepsInd (Mod regs rules dms) or u l ->
    forall filt,
      M.KeysDisj (defs (hide l)) filt ->
      SubstepsInd (Mod regs rules (filterDms dms filt)) or u l.
Proof.
  induction 2; intros; subst; simpl; [constructor|].
  (* eapply SubstepsCons; eauto. *)
  admit.
Qed.

Lemma stepInd_dms_weakening:
  forall regs rules dms or u l,
    DisjList (getCalls (Mod regs rules dms)) (getDefs (Mod regs rules dms)) ->
    StepInd (Mod regs rules dms) or u l ->
    forall filt,
      M.KeysDisj (defs l) filt ->
      StepInd (Mod regs rules (filterDms dms filt)) or u l.
Proof.
  induction 2; intros.
  constructor.
  - apply substepInd_dms_weakening; auto.
  - apply filterDms_wellHidden; auto.
Qed.

Lemma step_dms_weakening:
  forall regs rules dms or u l,
    DisjList (getCalls (Mod regs rules dms))
             (getDefs (Mod regs rules dms)) ->
    Step (Mod regs rules dms) or u l ->
    forall filt,
      M.KeysDisj (defs l) filt ->
      Step (Mod regs rules (filterDms dms filt)) or u l.
Proof.
  intros; subst; simpl.
  apply step_consistent; apply step_consistent in H0.
  apply stepInd_dms_weakening; auto.
Qed.

