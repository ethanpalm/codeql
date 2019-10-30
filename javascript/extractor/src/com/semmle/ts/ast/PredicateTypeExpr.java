package com.semmle.ts.ast;

import com.semmle.js.ast.SourceLocation;
import com.semmle.js.ast.Visitor;

/**
 * A type of form <tt>E is T</tt> where <tt>E</tt> is a parameter name or <tt>this</tt> and
 * <tt>T</tt> is a type.
 */
public class PredicateTypeExpr extends TypeExpression {
  private final ITypeExpression expression;
  private final ITypeExpression type;

  public PredicateTypeExpr(SourceLocation loc, ITypeExpression expression, ITypeExpression type) {
    super("PredicateTypeExpr", loc);
    this.expression = expression;
    this.type = type;
  }

  /** Returns the <tt>E</tt> in <tt>E is T</tt>. */
  public ITypeExpression getExpression() {
    return expression;
  }

  /** Returns the <tt>T</tt> in <tt>E is T</tt>. */
  public ITypeExpression getTypeExpr() {
    return type;
  }

  @Override
  public <C, R> R accept(Visitor<C, R> v, C c) {
    return v.visit(this, c);
  }
}
