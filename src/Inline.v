Require Import Bool List String.
Require Import Lib.CommonTactics Lib.Struct Lib.StringBound Lib.ilist Lib.Word Lib.FnMap.
Require Import Syntax.

Require Import FunctionalExtensionality.

Set Implicit Arguments.

Ltac destruct_existT :=
  repeat match goal with
           | [H: existT _ _ _ = existT _ _ _ |- _] =>
             (apply Eqdep.EqdepTheory.inj_pair2 in H; subst)
         end.

Section Phoas.
  Variable type: Kind -> Type.

  Definition inlineArg {argT retT} (a: Expr type argT)
             (m: fullType type argT -> Action type retT): Action type retT :=
    Let_ a m.

  Fixpoint getMethod (n: string) (dms: list (DefMethT type)) :=
    match dms with
      | nil => None
      | {| attrName := mn; attrType := mb |} :: dms' =>
        if string_dec n mn then Some mb else getMethod n dms'
    end.

  Fixpoint appendAction {retT1 retT2} (a1: Action type retT1)
           (a2: type retT1 -> Action type retT2): Action type retT2 :=
    match a1 with
      | MCall name sig ar cont => MCall name sig ar (fun a => appendAction (cont a) a2)
      | Let_ _ ar cont => Let_ ar (fun a => appendAction (cont a) a2)
      | ReadReg reg k cont => ReadReg reg k (fun a => appendAction (cont a) a2)
      | WriteReg reg _ e cont => WriteReg reg e (appendAction cont a2)
      | IfElse ce _ ta fa cont => IfElse ce ta fa (fun a => appendAction (cont a) a2)
      | Assert_ ae cont => Assert_ ae (appendAction cont a2)
      | Return e => Let_ e a2
    end.
  
  Lemma appendAction_assoc:
    forall {retT1 retT2 retT3}
           (a1: Action type retT1) (a2: type retT1 -> Action type retT2)
           (a3: type retT2 -> Action type retT3),
      appendAction a1 (fun t => appendAction (a2 t) a3) = appendAction (appendAction a1 a2) a3.
  Proof.
    induction a1; simpl; intuition idtac; f_equal; try extensionality x; eauto.
  Qed.

  Fixpoint inlineDm {retT} (a: Action type retT)
           (dm: DefMethT type): Action type retT :=
    match a with
      | MCall name sig ar cont =>
        if string_dec name (attrName dm) then
          match SignatureT_dec (objType (attrType dm)) sig with
            | left e => appendAction (inlineArg ar (eq_rect _ _ (objVal (attrType dm)) _ e))
                                     (* (fun ak => inlineDm (cont ak) dm) *) cont
            | right _ =>
              MCall name sig ar (fun ak => inlineDm (cont ak) dm)
          end
        else
          MCall name sig ar (fun ak => inlineDm (cont ak) dm)
      | Let_ _ ar cont => Let_ ar (fun a => inlineDm (cont a) dm)
      | ReadReg reg k cont => ReadReg reg k (fun a => inlineDm (cont a) dm)
      | WriteReg reg _ e cont => WriteReg reg e (inlineDm cont dm)
      | IfElse ce _ ta fa cont => IfElse ce (inlineDm ta dm) (inlineDm fa dm)
                                         (fun a => inlineDm (cont a) dm)
      | Assert_ ae cont => Assert_ ae (inlineDm cont dm)
      | Return e => Return e
    end.

  Fixpoint inlineDms {retT} (a: Action type retT)
           (dms: list (DefMethT type)): Action type retT :=
    match dms with
      | nil => a
      | dm :: dms' => inlineDms (inlineDm a dm) dms'
    end.

  Fixpoint inlineDmsRep {retT} (a: Action type retT) (dms: list (DefMethT type))
           (countdown: nat): Action type retT :=
    match countdown with
      | O => a
      | S cd => inlineDmsRep (inlineDms a dms) dms cd
    end.

  Section Countdown.
    Variable countdown: nat.

    Definition inlineToRule (r: Attribute (Action type (Bit 0)))
               (dms: list (DefMethT type)): Attribute (Action type (Bit 0)) :=
      match r with
        | {| attrName := rn; attrType := ra |} =>
          {| attrName := rn;
             attrType := inlineDmsRep ra dms countdown |}
      end.

    Fixpoint inlineToRules (rules: list (Attribute (Action type (Bit 0))))
             (dms: list (DefMethT type)): list (Attribute (Action type (Bit 0))) :=
      match rules with
        | nil => nil
        | r :: rules' => (inlineToRule r dms) :: (inlineToRules rules' dms)
      end.

    Lemma inlineToRules_In:
      forall r rules dms, In r rules -> In (inlineToRule r dms) (inlineToRules rules dms).
    Proof.
      induction rules; intros; inv H.
      - left; reflexivity.
      - right; apply IHrules; auto.
    Qed.

    Definition inlineToDm (n: string) {argT retT} (m: type argT -> Action type retT)
               (dms: list (DefMethT type)): type argT -> Action type retT :=
      fun a => inlineDmsRep (m a) dms countdown.

    Fixpoint inlineToDms (dms: list (DefMethT type)): list (DefMethT type) :=
      match dms with
        | nil => nil
        | {| attrName := n; attrType := {| objType := s; objVal := a |} |} :: dms' =>
          {| attrName := n; attrType := {| objType := s; objVal := inlineToDm n a dms |} |}
            :: (inlineToDms dms')
      end.

    Definition inlineMod (m1 m2: Modules type): Modules type :=
      match m1, m2 with
        | Mod regs1 r1 dms1, Mod regs2 r2 dms2 =>
          Mod (regs1 ++ regs2) (inlineToRules (r1 ++ r2) (dms1 ++ dms2))
              (inlineToDms (dms1 ++ dms2))
        | _, _ => m1 (* undefined *)
      end.

  End Countdown.

End Phoas.

Section PhoasTT.

  Definition typeTT (k: Kind): Type := unit.

  Definition fullTypeTT (k: FullKind): Type :=
    match k with
      | SyntaxKind k' => typeTT k'
      | NativeKind t c => t
    end.

  Definition getTT (k: FullKind): fullTypeTT k :=
    match k with
      | SyntaxKind _ => tt
      | NativeKind t c => c
    end.
  
  Section NoCalls.
    (* Necessary condition for inlining correctness *)
    Fixpoint noCalls {retT} (a: Action typeTT retT) :=
      match a with
        | MCall _ _ _ _ => false
        | Let_ _ ar cont => noCalls (cont (getTT _))
        | ReadReg reg k cont => noCalls (cont (getTT _))
        | WriteReg reg _ e cont => noCalls cont
        | IfElse ce _ ta fa cont => (noCalls ta) && (noCalls fa) && (noCalls (cont tt))
        | Assert_ ae cont => noCalls cont
        | Return e => true
      end.

    Fixpoint noCallsRules (rules: list (Attribute (Action typeTT (Bit 0)))) :=
      match rules with
        | nil => true
        | {| attrType := r |} :: rules' => (noCalls r) && (noCallsRules rules')
      end.

    Fixpoint noCallsDms (dms: list (DefMethT typeTT)) :=
      match dms with
        | nil => true
        | {| attrType := {| objVal := dm |} |} :: dms' =>
          (noCalls (dm tt)) && (noCallsDms dms')
      end.

    Fixpoint noCallsMod (m: Modules typeTT) :=
      match m with
        | Mod _ rules dms => (noCallsRules rules) && (noCallsDms dms)
        | ConcatMod m1 m2 => (noCallsMod m1) && (noCallsMod m2)
      end.

  End NoCalls.

End PhoasTT.

Require Import Semantics.

Lemma action_olds_ext:
  forall retK a olds1 olds2 news calls (retV: type retK),
    FnMap.Sub olds1 olds2 ->
    SemAction olds1 a news calls retV ->
    SemAction olds2 a news calls retV.
Proof.
  induction a; intros.
  - invertAction H1; econstructor; eauto.
  - invertAction H1; econstructor; eauto.
  - invertAction H1; econstructor; eauto.
    repeat autounfold with MapDefs; repeat autounfold with MapDefs in H1.
    rewrite <-H1; symmetry; apply H0; unfold InMap, find; rewrite H1; discriminate.
  - invertAction H0; econstructor; eauto.
  - invertAction H1.
    remember (evalExpr e) as cv; destruct cv; dest.
    + eapply SemIfElseTrue; eauto.
    + eapply SemIfElseFalse; eauto.
  - invertAction H0; econstructor; eauto.
  - invertAction H0; econstructor; eauto.
Qed.

Lemma appendAction_SemAction_1:
  forall retK1 retK2 a1 a2 olds1 olds2 news1 news2 calls1 calls2
         (retV1: type retK1) (retV2: type retK2),
    Disj olds1 olds2 ->
    SemAction olds1 a1 news1 calls1 retV1 ->
    SemAction olds2 (a2 retV1) news2 calls2 retV2 ->
    SemAction (union olds1 olds2) (appendAction a1 a2)
              (union news1 news2) (union calls1 calls2) retV2.
Proof.
  induction a1; intros.

  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H1 H2); econstructor; eauto.
  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H1 H2); econstructor; eauto.
  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H3 H2); econstructor; eauto.
    repeat autounfold with MapDefs; repeat autounfold with MapDefs in H1.
    rewrite H1; reflexivity.
  - invertAction H0; specialize (IHa1 _ _ _ _ _ _ _ _ _ H H0 H1); econstructor; eauto.

  - invertAction H1.
    simpl; remember (evalExpr e) as cv; destruct cv; dest; subst.
    + eapply SemIfElseTrue.
      * eauto.
      * eapply action_olds_ext.
        { instantiate (1:= olds1); apply Sub_union. }
        { exact H1. }
      * eapply H; eauto.
      * rewrite union_assoc; reflexivity.
      * rewrite union_assoc; reflexivity.
    + eapply SemIfElseFalse.
      * eauto.
      * eapply action_olds_ext.
        { instantiate (1:= olds1); apply Sub_union. }
        { exact H1. }
      * eapply H; eauto.
      * rewrite union_assoc; reflexivity.
      * rewrite union_assoc; reflexivity.

  - invertAction H0; specialize (IHa1 _ _ _ _ _ _ _ _ _ H H0 H1); econstructor; eauto.
  - invertAction H0; map_simpl_G; econstructor.
    eapply action_olds_ext; eauto.
    rewrite Disj_union_unionR; auto.
    apply Sub_unionR.
    
Qed.

Lemma appendAction_SemAction_2:
  forall retK1 retK2 a1 a2 olds1 olds2 news1 news2 calls1 calls2
         (retV1: type retK1) (retV2: type retK2),
    FnMap.Sub olds1 olds2 ->
    SemAction olds1 a1 news1 calls1 retV1 ->
    SemAction olds2 (a2 retV1) news2 calls2 retV2 ->
    SemAction olds2 (appendAction a1 a2) (union news1 news2) (union calls1 calls2) retV2.
Proof.
  induction a1; intros.

  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H1 H2); econstructor; eauto.
  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H1 H2); econstructor; eauto.
  - invertAction H1; specialize (H _ _ _ _ _ _ _ _ _ _ H0 H3 H2); econstructor; eauto.
    specialize (H0 r); unfold InMap in H0; rewrite H1 in H0; specialize (H0 (opt_discr _)).
    rewrite <-H1; unfold find; auto.
  - invertAction H0; specialize (IHa1 _ _ _ _ _ _ _ _ _ H H0 H1); econstructor; eauto.

  - invertAction H1.
    simpl; remember (evalExpr e) as cv; destruct cv; dest; subst.
    + eapply SemIfElseTrue.
      * eauto.
      * eapply action_olds_ext; eauto.
      * eapply H; eauto.
      * rewrite union_assoc; reflexivity.
      * rewrite union_assoc; reflexivity.
    + eapply SemIfElseFalse.
      * eauto.
      * eapply action_olds_ext; eauto.
      * eapply H; eauto.
      * rewrite union_assoc; reflexivity.
      * rewrite union_assoc; reflexivity.

  - invertAction H0; specialize (IHa1 _ _ _ _ _ _ _ _ _ H H0 H1); econstructor; eauto.
  - invertAction H0; map_simpl_G; econstructor; eauto.
Qed.

Inductive WfmActionSem: list string -> forall {retT}, Action type retT -> Prop :=
| WfmMCallSem:
    forall ll name sig ar {retT} cont (Hnin: ~ In name ll),
      (forall t, WfmActionSem (name :: ll) (cont t)) ->
      WfmActionSem ll (MCall (lretT:= retT) name sig ar cont)
| WfmLetSem:
    forall ll {argT retT} ar cont,
      (forall t, WfmActionSem ll (cont t)) ->
      WfmActionSem ll (Let_ (lretT':= argT) (lretT:= retT) ar cont)
| WfmReadRegSem:
    forall ll {retT} reg k cont,
      (forall t, WfmActionSem ll (cont t)) ->
      WfmActionSem ll (ReadReg (lretT:= retT) reg k cont)
| WfmWriteRegSem:
    forall ll {writeT retT} reg e cont,
      WfmActionSem ll cont ->
      WfmActionSem ll (WriteReg (k:= writeT) (lretT:= retT) reg e cont)
| WfmIfElseSem:
    forall ll {retT1 retT2} ce ta fa cont,
      WfmActionSem ll (appendAction (retT1:= retT1) (retT2:= retT2) ta cont) ->
      WfmActionSem ll (appendAction (retT1:= retT1) (retT2:= retT2) fa cont) ->
      WfmActionSem ll (IfElse ce ta fa cont)
| WfmAssertSem:
    forall ll {retT} e cont,
      WfmActionSem ll cont ->
      WfmActionSem ll (Assert_ (lretT:= retT) e cont)
| WfmReturnSem:
    forall ll {retT} (e: Expr type (SyntaxKind retT)), WfmActionSem ll (Return e).

Hint Constructors WfmActionSem.

Lemma WfmActionSem_init_sub:
  forall {retK} (a: Action type retK) ll1
         (Hwfm: WfmActionSem ll1 a) ll2
         (Hin: forall k, In k ll2 -> In k ll1),
    WfmActionSem ll2 a.
Proof.
  induction 1; intros; simpl; intuition.

  econstructor; eauto; intros.
  apply H0; eauto.
  intros; inv H1; intuition.
Qed.

Lemma WfmActionSem_append_1':
  forall {retT2} a3 ll,
    WfmActionSem ll a3 ->
    forall {retT1} (a1: Action type retT1) (a2: type retT1 -> Action type retT2),
      a3 = appendAction a1 a2 -> WfmActionSem ll a1.
Proof.
  induction 1; intros.

  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate.
    + inv H1; destruct_existT; econstructor; eauto.
    + inv H1; destruct_existT; econstructor.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    constructor.
    + eapply IHWfmActionSem1; eauto; apply appendAction_assoc.
    + eapply IHWfmActionSem2; eauto; apply appendAction_assoc.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate.
Qed.

Lemma WfmActionSem_append_1:
  forall {retT1 retT2} (a1: Action type retT1) (a2: type retT1 -> Action type retT2) ll,
    WfmActionSem ll (appendAction a1 a2) ->
    WfmActionSem ll a1.
Proof. intros; eapply WfmActionSem_append_1'; eauto. Qed.

Lemma WfmActionSem_append_2':
  forall {retT2} a3 ll,
    WfmActionSem ll a3 ->
    forall {retT1} (a1: Action type retT1) (a2: type retT1 -> Action type retT2),
      a3 = appendAction a1 a2 ->
      forall t, WfmActionSem ll (a2 t).
Proof.
  induction 1; intros.

  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    apply WfmActionSem_init_sub with (ll1:= meth :: ll); [|intros; right; assumption].
    eapply H0; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    + eapply H0; eauto.
    + apply H.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    eapply H0; eauto.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    eapply IHWfmActionSem; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    eapply IHWfmActionSem1; eauto.
    apply appendAction_assoc.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    eapply IHWfmActionSem; eauto.
  - destruct a1; simpl in *; try discriminate.

    Grab Existential Variables.
    { exact (defaultConstFullT _). }    
    { exact (defaultConstFullT _). }    
    { exact (evalConstT (getDefaultConst _)). }    
Qed.

Lemma WfmActionSem_append_2:
  forall {retT1 retT2} (a1: Action type retT1) (a2: type retT1 -> Action type retT2) ll,
    WfmActionSem ll (appendAction a1 a2) ->
    forall t, WfmActionSem ll (a2 t).
Proof. intros; eapply WfmActionSem_append_2'; eauto. Qed.

Lemma WfmActionSem_cmMap:
  forall {retK} olds (a: Action type retK) news calls retV ll
         (Hsem: SemAction olds a news calls retV)
         (Hwfm: WfmActionSem ll a)
         lb (Hin: In lb ll),
    find lb calls = None.
Proof.
  induction 1; intros; simpl; subst; intuition idtac; inv Hwfm; destruct_existT.

  - rewrite find_add_2.
    { apply IHHsem; eauto.
      specialize (H2 mret); eapply WfmActionSem_init_sub; eauto.
      intros; right; assumption.
    }
    { unfold string_eq; destruct (string_dec _ _); [subst; elim Hnin; assumption|intuition]. }
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - assert (find lb calls1 = None).
    { eapply IHHsem1; eauto.
      eapply WfmActionSem_append_1; eauto.
    }
    assert (find lb calls2 = None).
    { eapply IHHsem2; eauto.
      eapply WfmActionSem_append_2; eauto.
    }
    repeat autounfold with MapDefs in *.
    rewrite H, H0; reflexivity.
  - assert (find lb calls1 = None).
    { eapply IHHsem1; eauto.
      eapply WfmActionSem_append_1; eauto.
    }
    assert (find lb calls2 = None).
    { eapply IHHsem2; eauto.
      eapply WfmActionSem_append_2; eauto.
    }
    repeat autounfold with MapDefs in *.
    rewrite H, H0; reflexivity.
  - eapply IHHsem; eauto.
Qed.

Lemma WfmActionSem_append_3':
  forall {retT2} a3 ll,
    WfmActionSem ll a3 ->
    forall {retT1} (a1: Action type retT1) (a2: type retT1 -> Action type retT2),
      a3 = appendAction a1 a2 ->
      forall olds1 olds2 news1 news2 calls1 calls2 retV1 retV2,
      SemAction olds1 a1 news1 calls1 retV1 ->
      SemAction olds2 (a2 retV1) news2 calls2 retV2 ->
      forall lb, find lb calls1 = None \/ find lb calls2 = None.
Proof.
  induction 1; intros; simpl; intuition idtac; destruct a1; simpl in *; try discriminate.
  
  - inv H1; destruct_existT.
    invertAction H2; specialize (H x).
    specialize (H0 _ _ _ _ eq_refl _ _ _ _ _ _ _ _ H1 H3 lb).
    destruct H0; [|right; assumption].
    destruct (string_dec lb meth); [subst; right|left].
    + pose proof (WfmActionSem_append_2 _ _ H retV1).
      eapply WfmActionSem_cmMap; eauto.
    + rewrite find_add_2; [assumption|unfold string_eq; destruct (string_dec _ _); intuition].

  - inv H1; destruct_existT; invertAction H2; eapply H0; eauto.
  - inv H1; destruct_existT; invertAction H2; left; reflexivity.
  - inv H1; destruct_existT; invertAction H2; eapply H0; eauto.
  - inv H0; destruct_existT; invertAction H1; eapply IHWfmActionSem; eauto.
  - inv H1; destruct_existT.
    invertAction H2.
    destruct (evalExpr e); dest; subst.
    + specialize (@IHWfmActionSem1 _ (appendAction a1_1 a) a2 (appendAction_assoc _ _ _)).
      eapply IHWfmActionSem1; eauto.
      instantiate (1:= union x x1); instantiate (1:= olds1).
      eapply appendAction_SemAction_2; eauto.
      intuition.
    + specialize (@IHWfmActionSem2 _ (appendAction a1_2 a) a2 (appendAction_assoc _ _ _)).
      eapply IHWfmActionSem2; eauto.
      instantiate (1:= union x x1); instantiate (1:= olds1).
      eapply appendAction_SemAction_2; eauto.
      intuition.
    
  - inv H0; destruct_existT; invertAction H1; eapply IHWfmActionSem; eauto.
Qed.

Lemma WfmActionSem_append_3:
  forall {retT1 retT2} (a1: Action type retT1) (a2: type retT1 -> Action type retT2) ll,
    WfmActionSem ll (appendAction a1 a2) ->
    forall olds1 olds2 news1 news2 calls1 calls2 retV1 retV2,
      SemAction olds1 a1 news1 calls1 retV1 ->
      SemAction olds2 (a2 retV1) news2 calls2 retV2 ->
      forall lb, find lb calls1 = None \/ find lb calls2 = None.
Proof. intros; eapply WfmActionSem_append_3'; eauto. Qed.

Lemma WfmActionSem_init:
  forall {retK} (a: Action type retK) ll
         (Hwfm: WfmActionSem ll a),
    WfmActionSem nil a.
Proof. intros; eapply WfmActionSem_init_sub; eauto; intros; inv H. Qed.

Lemma WfmActionSem_MCall:
  forall {retK} olds a news calls (retV: type retK) dmn
         (Hsem: SemAction olds a news calls retV)
         (Hwfm: WfmActionSem [dmn] a),
    complement calls [dmn] = calls.
Proof.
  induction 1; intros; inv Hwfm; destruct_existT.

  - rewrite complement_add_2 by assumption; f_equal.
    apply IHHsem.
    specialize (H2 mret).
    apply (WfmActionSem_init_sub H2 [dmn]).
    intros; inv H; intuition.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - rewrite complement_union; f_equal.
    + eapply IHHsem1; eauto.
      eapply WfmActionSem_append_1; eauto.
    + eapply IHHsem2; eauto.
      eapply WfmActionSem_append_2; eauto.
  - rewrite complement_union; f_equal.
    + eapply IHHsem1; eauto.
      eapply WfmActionSem_append_1; eauto.
    + eapply IHHsem2; eauto.
      eapply WfmActionSem_append_2; eauto.
  - eapply IHHsem; eauto.
  - map_simpl_G; reflexivity.
Qed.

Lemma inlineDm_not_called:
  forall {retK} olds (a: Action type retK) news calls retV dm
         (Hsem: SemAction olds a news calls retV)
         (Hcol: find (attrName dm) calls = None),
    SemAction olds (inlineDm a dm) news calls retV.
Proof.
  induction 1; intros; simpl; subst; intuition idtac.

  - destruct (string_dec meth dm); [subst; map_simpl Hcol; discriminate|].
    econstructor; eauto.
    rewrite find_add_2 in Hcol;
      [|unfold string_eq; destruct (string_dec _ _); intuition].
    apply IHHsem; auto.
  - econstructor; eauto.
  - econstructor; eauto.
  - econstructor; eauto.
  - eapply SemIfElseTrue; eauto.
    + eapply IHHsem1.
      repeat autounfold with MapDefs in *; destruct (calls1 dm); intuition.
    + eapply IHHsem2.
      repeat autounfold with MapDefs in *; destruct (calls1 dm); [discriminate|assumption].
  - eapply SemIfElseFalse; eauto.
    + eapply IHHsem1.
      repeat autounfold with MapDefs in *; destruct (calls1 dm); intuition.
    + eapply IHHsem2.
      repeat autounfold with MapDefs in *; destruct (calls1 dm); [discriminate|assumption].
  - econstructor; eauto.
  - econstructor; eauto.
Qed.

Section Preliminaries.

  Lemma SemMod_singleton:
    forall rules olds news dm dmMap cmMap,
      SemMod rules olds None news (dm :: nil) dmMap cmMap ->
      DomainOf dmMap ((attrName dm) :: nil) ->
      exists argV retV,
        dm = {| attrName := attrName dm;
                attrType := {| objType := {| arg := arg (objType (attrType dm));
                                             ret := ret (objType (attrType dm)) |};
                               objVal := objVal (attrType dm) |} |} /\
        dmMap = add (attrName dm) {| objVal := (argV, retV) |} empty /\
        SemAction olds (objVal (attrType dm) argV) news cmMap retV.
  Proof.
    intros.
    invertSemMod H.

    - invertSemMod HSemMod.
      exists argV; exists retV.
      split.
      
      + destruct dm as [dmn [[ ] ]]; simpl; reflexivity.
      + split; [reflexivity|].
        map_simpl_G; assumption.

    - invertSemMod HSemMod; exfalso.
      specialize (H0 (attrName dm)); destruct H0.
      specialize (H0 (or_introl eq_refl)).
      unfold InMap in H0; elim H0; reflexivity.
  Qed.

  Lemma inlineDm_prop:
    forall olds1 olds2 retK2 a2
           dm rules news1 news2 dmMap1 cmMap1 cmMap2
           (retV2: type retK2),
      Disj olds1 olds2 -> Disj news1 news2 -> Disj cmMap1 cmMap2 ->
      
      WfmActionSem nil a2 ->
      SemAction olds2 a2 news2 cmMap2 retV2 ->
      
      find (attrName dm) cmMap2 = find (attrName dm) dmMap1 -> (* labels match *)
      DomainOf dmMap1 ((attrName dm) :: nil) -> (* dm is actually called *)
      
      SemMod rules olds1 None news1 (dm :: nil) dmMap1 cmMap1 ->
      SemAction (union olds1 olds2) (inlineDm a2 dm)
                (union news1 news2)
                (union cmMap1 (complement cmMap2 ((attrName dm) :: nil)))
                retV2.
  Proof.
    intros; pose proof (SemMod_singleton H6 H5); clear H5 H6; dest.
    destruct dm as [dmn [[ ]]]; simpl in *; inv H5.
    map_simpl H4.

    generalize dependent olds2; generalize dependent news2; generalize dependent cmMap2.
    induction a2; intros.

    - invertAction H5.
      simpl; destruct (string_dec meth dmn); [subst|].

      + clear H. (* don't need IH for this case *)

        map_simpl H4.
        apply opt_some_eq in H4; subst.
        apply typed_type_eq in H4; dest.
        generalize dependent H5; subst; intros.
        inv H.

        destruct (SignatureT_dec _ _); [|elim n; reflexivity].
        simpl in *; rewrite <-Eqdep.EqdepTheory.eq_rect_eq; clear e0.

        econstructor; eauto.
        apply appendAction_SemAction_1 with (retV1:= x0); auto.
        map_simpl_G.

        inv H2; destruct_existT.
        specialize (H8 x0).
        pose proof (WfmActionSem_MCall H5 H8); rewrite H.
        assumption.

      + rewrite find_add_2 in H4
          by (unfold string_eq; destruct (string_dec _ _); [elim n; assumption|reflexivity]).
        econstructor; eauto.

        * instantiate (1:= union cmMap1 (complement x2 [dmn])); instantiate (1:= x1).

          clear -n H1.
          unfold Disj in H1.
          apply Equal_eq; repeat autounfold with MapDefs; intros.
          specialize (H1 k).
          destruct H1.

          { unfold find in H; rewrite H.
            destruct (in_dec _ _ _).
            { inv i; [|inv H0].
              unfold string_eq; destruct (string_dec _ _); [elim n; assumption|reflexivity].
            }
            { unfold string_eq; destruct (string_dec _ _); reflexivity. }
          }
          { destruct (cmMap1 k).
            { unfold string_eq; destruct (string_dec _ _); [|reflexivity].
              subst; map_simpl H; discriminate.
            }
            { destruct (in_dec _ _ _).
              { inv i; [|inv H0].
                unfold string_eq; destruct (string_dec _ _); [elim n; assumption|reflexivity].
              }
              { unfold string_eq; destruct (string_dec _ _); reflexivity. }
            }
          }

        * apply H; auto.
          { inv H2; destruct_existT.
            specialize (H10 x1).
            eapply WfmActionSem_init; eauto.
          }
          { eapply Disj_add_2; eauto. }

    - invertAction H5; inv H2; destruct_existT.
      simpl; econstructor; eauto.
    - invertAction H5; inv H2; destruct_existT.
      simpl; econstructor; eauto.
      apply Disj_find_union; eauto.
    - invertAction H3; inv H2; destruct_existT.
      simpl; econstructor; eauto.
      + instantiate (1:= union news1 x1).
        apply Equal_eq; repeat autounfold with MapDefs; intros.
        specialize (H0 k0); destruct H0.
        * unfold find in H0; rewrite H0.
          unfold string_eq; destruct (string_dec _ _); reflexivity.
        * destruct (news1 k0).
          { unfold string_eq; destruct (string_dec _ _); [|reflexivity].
            subst; map_simpl H0; inv H0.
          }
          { unfold string_eq; destruct (string_dec _ _); reflexivity. }
      + apply IHa2; auto.
        eapply Disj_add_2; eauto.

    - invertAction H5; inv H2; destruct_existT.
      remember (evalExpr e) as cv; destruct cv; dest; subst.

      + remember (find dmn x2) as dmv1.
        destruct dmv1.

        * assert (t = {| objType := {| arg := arg; ret := ret |}; objVal := (x, x0) |}); subst.
          { repeat autounfold with MapDefs in *.
            rewrite <-Heqdmv1 in H4; inv H4; reflexivity.
          }
          simpl; eapply SemIfElseTrue.

          { auto. }
          { eapply IHa2_1. 
            { eapply WfmActionSem_append_1; eauto. }
            { instantiate (1:= x2); eapply Disj_union_1; eauto. }
            { auto. }
            { instantiate (1:= x1); eapply Disj_union_1; eauto. }
            { assumption. }
            { exact H2. }
          }
          { instantiate (1:= x4); instantiate (1:= x3).
            apply inlineDm_not_called.
            { eapply action_olds_ext; eauto.
              rewrite Disj_union_unionR by assumption.
              apply Sub_unionR.
            }
            { pose proof (WfmActionSem_append_3 _ H11 H2 H5 dmn).
              destruct H6; [|assumption].
              rewrite H6 in Heqdmv1; discriminate.
            }
          }
          { apply union_assoc. }
          { pose proof (WfmActionSem_append_3 _ H11 H2 H5 dmn).
            destruct H6; [rewrite H6 in Heqdmv1; discriminate|].
            assert (complement x4 [dmn] = x4).
            { clear -H6.
              apply Equal_eq; repeat autounfold with MapDefs in *; intros.
              destruct (in_dec _ _ _); intuition idtac.
              inv i; [auto|inv H].
            }
            rewrite complement_union; rewrite H8.
            apply union_assoc.
          }

        * simpl; eapply SemIfElseTrue.

          { auto. }
          { instantiate (1:= x5); instantiate (1:= x2); instantiate (1:= x1).
            apply inlineDm_not_called.
            { eapply action_olds_ext; eauto.
              rewrite Disj_union_unionR by assumption.
              apply Sub_unionR.
            }
            { auto. }
          }
          { apply H.
            { eapply WfmActionSem_append_2; eauto. }
            { instantiate (1:= x4); eapply Disj_union_2; eauto. }
            { repeat autounfold with MapDefs in *.
              rewrite <-Heqdmv1 in H4; assumption.
            }
            { instantiate (1:= x3); eapply Disj_union_2; eauto. }
            { assumption. }
            { assumption. }
          }
          { pose proof (Disj_union_1 H0); pose proof (Disj_union_2 H0).
            rewrite Disj_union_unionR by assumption; unfold unionR.
            rewrite <-union_assoc; f_equal.
            rewrite Disj_union_unionR with (m1:= news1) by assumption; unfold unionR.
            reflexivity.
          }
          { pose proof (Disj_union_1 H1); pose proof (Disj_union_2 H1).
            rewrite union_assoc.
            apply Disj_comm in H6; rewrite Disj_union_unionR with (m2:= cmMap1) by assumption.
            unfold unionR; rewrite <-union_assoc; f_equal.
            assert (complement x2 [dmn] = x2).
            { clear -Heqdmv1.
              apply Equal_eq; repeat autounfold with MapDefs in *; intros.
              destruct (in_dec _ _ _); [|reflexivity].
              inv i; [assumption|inv H].
            }
            rewrite <-H9 at 2; apply complement_union.
          }

      + remember (find dmn x2) as dmv1.
        destruct dmv1.

        * assert (t = {| objType := {| arg := arg; ret := ret |}; objVal := (x, x0) |}); subst.
          { repeat autounfold with MapDefs in *.
            rewrite <-Heqdmv1 in H4; inv H4; reflexivity.
          }
          simpl; eapply SemIfElseFalse.

          { auto. }
          { eapply IHa2_2. 
            { eapply WfmActionSem_append_1; eauto. }
            { instantiate (1:= x2); eapply Disj_union_1; eauto. }
            { auto. }
            { instantiate (1:= x1); eapply Disj_union_1; eauto. }
            { assumption. }
            { exact H2. }
          }
          { instantiate (1:= x4); instantiate (1:= x3).
            apply inlineDm_not_called.
            { eapply action_olds_ext; eauto.
              rewrite Disj_union_unionR by assumption.
              apply Sub_unionR.
            }
            { pose proof (WfmActionSem_append_3 _ H15 H2 H5 dmn).
              destruct H6; [|assumption].
              rewrite H6 in Heqdmv1; discriminate.
            }
          }
          { apply union_assoc. }
          { pose proof (WfmActionSem_append_3 _ H15 H2 H5 dmn).
            destruct H6; [rewrite H6 in Heqdmv1; discriminate|].
            assert (complement x4 [dmn] = x4).
            { clear -H6.
              apply Equal_eq; repeat autounfold with MapDefs in *; intros.
              destruct (in_dec _ _ _); intuition idtac.
              inv i; [auto|inv H].
            }
            rewrite complement_union; rewrite H8.
            apply union_assoc.
          }

        * simpl; eapply SemIfElseFalse.

          { auto. }
          { instantiate (1:= x5); instantiate (1:= x2); instantiate (1:= x1).
            apply inlineDm_not_called.
            { eapply action_olds_ext; eauto.
              rewrite Disj_union_unionR by assumption.
              apply Sub_unionR.
            }
            { auto. }
          }
          { apply H.
            { eapply WfmActionSem_append_2; eauto. }
            { instantiate (1:= x4); eapply Disj_union_2; eauto. }
            { repeat autounfold with MapDefs in *.
              rewrite <-Heqdmv1 in H4; assumption.
            }
            { instantiate (1:= x3); eapply Disj_union_2; eauto. }
            { assumption. }
            { assumption. }
          }
          { pose proof (Disj_union_1 H0); pose proof (Disj_union_2 H0).
            rewrite Disj_union_unionR by assumption; unfold unionR.
            rewrite <-union_assoc; f_equal.
            rewrite Disj_union_unionR with (m1:= news1) by assumption; unfold unionR.
            reflexivity.
          }
          { pose proof (Disj_union_1 H1); pose proof (Disj_union_2 H1).
            rewrite union_assoc.
            apply Disj_comm in H6; rewrite Disj_union_unionR with (m2:= cmMap1) by assumption.
            unfold unionR; rewrite <-union_assoc; f_equal.
            assert (complement x2 [dmn] = x2).
            { clear -Heqdmv1.
              apply Equal_eq; repeat autounfold with MapDefs in *; intros.
              destruct (in_dec _ _ _); [|reflexivity].
              inv i; [assumption|inv H].
            }
            rewrite <-H9 at 2; apply complement_union.
          }

    - invertAction H3; inv H2; destruct_existT.
      simpl; econstructor; eauto.
    - invertAction H3; simpl; map_simpl_G.
      map_simpl H4; inv H4.

  Qed.
  
  Lemma inlineDms_prop:
    forall dms olds1 olds2 retK2 a2 rules news1 news2 dmMap1 cmMap1 cmMap2
           (retV2: type retK2),
      SemAction olds2 a2 news2 cmMap2 retV2 ->
      dmMap1 = restrict cmMap2 (map (@attrName _) dms) ->
      SemMod rules olds1 None news1 dms dmMap1 cmMap1 ->
      SemAction (union olds1 olds2) (inlineDms a2 dms)
                (union news1 news2) (union cmMap1 (complement cmMap2 (map (@attrName _) dms)))
                retV2.
  Proof.
    admit.
  Qed.

  (* TODO: extend *)

End Preliminaries.

Section Facts.
  Variables (regs1 regs2: list RegInitT)
            (r1 r2: list (Attribute (Action type (Bit 0))))
            (dms1 dms2: list (DefMethT type)).

  Variable countdown: nat. (* TODO: weird *)

  Definition m1 := Mod regs1 r1 dms1.
  Definition m2 := Mod regs2 r2 dms2.

  Definition cm := ConcatMod m1 m2.
  Definition im := @inlineMod type countdown m1 m2.

  Lemma inline_correct_rule:
    forall r or nr cmMap,
      (* noCallsMod getDefault im = true -> *)
      LtsStep cm (Some r) or nr empty cmMap -> LtsStep im (Some r) or nr empty cmMap.
  Proof.
    admit.
  Qed.

End Facts.
    
    