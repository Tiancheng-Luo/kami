Require Import Bool List String Structures.Equalities.
Require Import Lib.Struct Lib.Word Lib.CommonTactics Lib.StringBound Lib.ilist Lib.FnMap Syntax Semantics.
Require Import FunctionalExtensionality Program.Equality Eqdep Eqdep_dec.

Set Implicit Arguments.

Notation "m [ k |--> v ]" := (add k v m) (at level 0).
Notation "m [ k |-> v ]" := (m [k |--> {| objVal := v |}]) (at level 0).
Notation "v === m .[ k ]" := (find k m = Some {| objVal := v |}) (at level 70).

Notation "m ~{ k |-> v }" := ((fun a => if weq a k then v else m a) : type (Vector (Bit _) _)) (at level 0).

Fixpoint SymSemAction k (a : Action type k) (rs rs' : RegsT) (cs : CallsT) (kf : RegsT -> CallsT -> type k -> Prop) : Prop :=
  match a with
  | MCall meth s marg cont =>
    forall mret,
      cs meth = None
      /\ SymSemAction (cont mret) rs rs' cs[meth |-> (evalExpr marg, mret)] kf
  | Let_ _ e cont =>
    SymSemAction (cont (evalExpr e)) rs rs' cs kf
  | ReadReg r _ cont =>
    exists regV,
      regV === rs.[r]
      /\ SymSemAction (cont regV) rs rs' cs kf
  | WriteReg r _ e cont =>
    rs' r = None
    /\ SymSemAction cont rs rs'[r |-> evalExpr e] cs kf
  | IfElse p _ a a' cont =>
    if evalExpr p
    then SymSemAction a rs rs' cs (fun rs'' cs' rv =>
                                     SymSemAction (cont rv) rs rs'' cs' kf)
    else SymSemAction a' rs rs' cs (fun rs'' cs' rv =>
                                      SymSemAction (cont rv) rs rs'' cs' kf)
  | Assert_ p cont =>
    evalExpr p = true
    -> SymSemAction cont rs rs' cs kf
                                 
  | Return e => kf rs' cs (evalExpr e)
  end.

Lemma union_add : forall A k (v : A) m1 m2,
  m1 k = None
  -> union m1 m2[k |--> v] = union m1[k |--> v] m2.
Proof.
  unfold union, add, unionL; intros.
  extensionality k0.
  destruct (string_dec k k0); subst.
  rewrite string_dec_eq.
  rewrite H; auto.
  rewrite string_dec_neq by assumption.
  auto.
Qed.

Lemma union_assoc : forall A (a b c : @Map A),
  union a (union b c) = union (union a b) c.
Proof.
  unfold union, unionL; intros.
  extensionality k.
  destruct (a k); auto.
Qed.

Lemma double_find : forall T (v1 v2 : type T) m k,
  v1 === m.[k]
  -> v2 === m.[k]
  -> v1 = v2.
Proof.
  intros.
  rewrite H in H0.
  injection H0; intro.
  apply inj_pair2 in H1.
  auto.
Qed.

Lemma SymSemAction_sound' : forall k (a : Action type k) rs rs' cs' rv,
  SemAction rs a rs' cs' rv
  -> forall rs'' cs kf, SymSemAction a rs rs'' cs kf
    -> kf (union rs'' rs') (union cs cs') rv.
Proof.
  induction 1; simpl; intuition.

  specialize (H0 mret); intuition.
  eapply IHSemAction in H2.
  subst.
  rewrite union_add by assumption; auto.

  destruct H0; intuition.
  specialize (double_find _ _ HRegVal H1); intro; subst.
  apply IHSemAction; auto.

  apply IHSemAction in H2.
  subst.
  rewrite union_add in * by assumption; auto.

  rewrite HTrue in *.
  apply IHSemAction1 in H1.
  apply IHSemAction2 in H1.
  subst.
  repeat rewrite union_assoc; auto.

  rewrite HFalse in *.
  apply IHSemAction1 in H1.
  apply IHSemAction2 in H1.
  subst.
  repeat rewrite union_assoc; auto.

  apply IHSemAction; auto.

  repeat rewrite union_empty_2; congruence.
Qed.

Theorem SymSemAction_sound : forall k (a : Action type k) rs rs' cs rv,
  SemAction rs a rs' cs rv
  -> forall kf, SymSemAction a rs empty empty kf
    -> kf rs' cs rv.
Proof.
  intros.
  apply (SymSemAction_sound' H) in H0.
  repeat rewrite union_empty_1 in H0.
  auto.
Qed.
