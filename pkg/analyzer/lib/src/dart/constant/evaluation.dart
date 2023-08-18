// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/ast/token.dart';
import 'package:analyzer/src/dart/constant/from_environment_evaluator.dart';
import 'package:analyzer/src/dart/constant/has_type_parameter_reference.dart';
import 'package:analyzer/src/dart/constant/potentially_constant.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/dart/element/type_system.dart' show TypeSystemImpl;
import 'package:analyzer/src/diagnostic/diagnostic.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_core.dart';
import 'package:analyzer/src/task/api/model.dart';
import 'package:analyzer/src/utilities/extensions/collection.dart';
import 'package:analyzer/src/utilities/extensions/object.dart';

class ConstantEvaluationConfiguration {
  final Map<AstNode, AstNode> _errorNodes = {};

  /// We evaluate constant values using expressions stored in elements.
  /// But these expressions don't have offsets set.
  /// This includes elements and expressions of the file being resolved.
  /// So, to make sure that we report errors at right offsets, we "replace"
  /// these constant expressions.
  ///
  /// A similar issue happens for enum values, which are desugared into
  /// synthetic [InstanceCreationExpression], which never had any offsets.
  /// So, we remember that any errors should be reported at the corresponding
  /// [EnumConstantDeclaration]s.
  void addErrorNode({
    required AstNode? fromElement,
    required AstNode? fromAst,
  }) {
    if (fromElement != null && fromAst != null) {
      _errorNodes[fromElement] = fromAst;
    }
  }

  AstNode errorNode(AstNode node) {
    return _errorNodes[node] ?? node;
  }
}

/// Helper class encapsulating the methods for evaluating constants and
/// constant instance creation expressions.
class ConstantEvaluationEngine {
  /// The set of variables declared on the command line using '-D'.
  final DeclaredVariables _declaredVariables;

  /// Whether the `non-nullable` feature is enabled.
  final bool _isNonNullableByDefault;

  final ConstantEvaluationConfiguration configuration;

  /// Initialize a newly created [ConstantEvaluationEngine].
  ///
  /// [declaredVariables] is the set of variables declared on the command
  /// line using '-D'.
  ConstantEvaluationEngine({
    required DeclaredVariables declaredVariables,
    required bool isNonNullableByDefault,
    required this.configuration,
  })  : _declaredVariables = declaredVariables,
        _isNonNullableByDefault = isNonNullableByDefault;

  /// Compute the constant value associated with the given [constant].
  void computeConstantValue(ConstantEvaluationTarget constant) {
    if (constant is Element) {
      var element = constant as Element;
      constant = element.declaration as ConstantEvaluationTarget;
    }

    var library = constant.library as LibraryElementImpl;
    if (constant is ParameterElementImpl) {
      if (constant is ConstVariableElement) {
        var defaultValue = constant.constantInitializer;
        if (defaultValue != null) {
          RecordingErrorListener errorListener = RecordingErrorListener();
          ErrorReporter errorReporter = ErrorReporter(
            errorListener,
            constant.source!,
            isNonNullableByDefault: library.isNonNullableByDefault,
          );
          // TODO(kallentu): Remove unwrapping of Constant.
          var dartConstant = defaultValue
              .accept(ConstantVisitor(this, library, errorReporter));
          var dartObject = dartConstant is DartObjectImpl ? dartConstant : null;
          constant.evaluationResult =
              EvaluationResultImpl(dartObject, errorListener.errors);
        } else {
          constant.evaluationResult = EvaluationResultImpl(
            _nullObject(library),
          );
        }
      }
    } else if (constant is VariableElementImpl) {
      var constantInitializer = constant.constantInitializer;
      if (constantInitializer != null) {
        RecordingErrorListener errorListener = RecordingErrorListener();
        ErrorReporter errorReporter = ErrorReporter(
          errorListener,
          constant.source!,
          isNonNullableByDefault: library.isNonNullableByDefault,
        );
        // TODO(kallentu): Remove unwrapping of Constant.
        var dartConstant = constantInitializer
            .accept(ConstantVisitor(this, library, errorReporter));
        var dartObject = dartConstant is DartObjectImpl ? dartConstant : null;
        // Only check the type for truly const declarations (don't check final
        // fields with initializers, since their types may be generic.  The type
        // of the final field will be checked later, when the constructor is
        // invoked).
        if (dartObject != null && constant.isConst) {
          if (!library.typeSystem.runtimeTypeMatch(dartObject, constant.type)) {
            // If the static types are mismatched, an error would have already
            // been reported.
            if (library.typeSystem.isAssignableTo(
                constantInitializer.typeOrThrow, constant.type)) {
              errorReporter.reportErrorForNode(
                  CompileTimeErrorCode.VARIABLE_TYPE_MISMATCH,
                  constantInitializer,
                  [dartObject.type, constant.type]);
            }
          }

          // Associate with the variable.
          dartObject = DartObjectImpl.forVariable(dartObject, constant);
        }

        if (dartObject != null) {
          var enumConstant = _enumConstant(constant);
          if (enumConstant != null) {
            dartObject.updateEnumConstant(
              index: enumConstant.index,
              name: enumConstant.name,
            );
          }
        }

        constant.evaluationResult =
            EvaluationResultImpl(dartObject, errorListener.errors);
      }
    } else if (constant is ConstructorElementImpl) {
      if (constant.isConst) {
        // No evaluation needs to be done; constructor declarations are only in
        // the dependency graph to ensure that any constants referred to in
        // initializer lists and parameter defaults are evaluated before
        // invocations of the constructor.
        constant.isConstantEvaluated = true;
      }
    } else if (constant is ElementAnnotationImpl) {
      var constNode = constant.annotationAst;
      var element = constant.element;
      if (element is PropertyAccessorElement) {
        // The annotation is a reference to a compile-time constant variable.
        // Just copy the evaluation result.
        VariableElementImpl variableElement =
            element.variable.declaration as VariableElementImpl;
        if (variableElement.evaluationResult != null) {
          constant.evaluationResult = variableElement.evaluationResult;
        } else {
          // This could happen in the event that the annotation refers to a
          // non-constant.  The error is detected elsewhere, so just silently
          // ignore it here.
          constant.evaluationResult = EvaluationResultImpl(null);
        }
      } else if (element is ConstructorElement &&
          element.isConst &&
          constNode.arguments != null) {
        RecordingErrorListener errorListener = RecordingErrorListener();
        ErrorReporter errorReporter = ErrorReporter(
          errorListener,
          constant.source,
          isNonNullableByDefault: library.isNonNullableByDefault,
        );
        ConstantVisitor constantVisitor =
            ConstantVisitor(this, library, errorReporter);
        final result = evaluateConstructorCall(
            library,
            constNode,
            element.returnType.typeArguments,
            constNode.arguments!.arguments,
            element,
            constantVisitor,
            errorReporter);
        // TODO(kallentu): Report the InvalidConstant returned from the
        // constructor call.
        final evaluationConstant = result is DartObjectImpl ? result : null;
        constant.evaluationResult =
            EvaluationResultImpl(evaluationConstant, errorListener.errors);
      } else {
        // This may happen for invalid code (e.g. failing to pass arguments
        // to an annotation which references a const constructor).  The error
        // is detected elsewhere, so just silently ignore it here.
        constant.evaluationResult = EvaluationResultImpl(null);
      }
    } else if (constant is VariableElement) {
      // constant is a VariableElement but not a VariableElementImpl.  This can
      // happen sometimes in the case of invalid user code (for example, a
      // constant expression that refers to a non-static field inside a generic
      // class will wind up referring to a FieldMember).  The error is detected
      // elsewhere, so just silently ignore it here.
    } else {
      // Should not happen.
      assert(false);
      AnalysisEngine.instance.instrumentationService
          .logError("Constant value computer trying to compute "
              "the value of a node of type ${constant.runtimeType}");
      return;
    }
  }

  /// Determine which constant elements need to have their values computed
  /// prior to computing the value of [constant], and report them using
  /// [callback].
  void computeDependencies(
      ConstantEvaluationTarget constant, ReferenceFinderCallback callback) {
    if (constant is ConstFieldElementImpl && constant.isEnumConstant) {
      var enclosing = constant.enclosingElement;
      if (enclosing is EnumElementImpl) {
        if (enclosing.name == 'values') {
          return;
        }
        if (constant.name == enclosing.name) {
          return;
        }
      }
    }

    ReferenceFinder referenceFinder = ReferenceFinder(callback);
    if (constant is ConstructorElement) {
      constant = constant.declaration;
    }
    if (constant is VariableElement) {
      var declaration = constant.declaration as VariableElementImpl;
      var initializer = declaration.constantInitializer;
      if (initializer != null) {
        initializer.accept(referenceFinder);
      }
    } else if (constant is ConstructorElementImpl) {
      if (constant.isConst) {
        var redirectedConstructor = getConstRedirectedConstructor(constant);
        if (redirectedConstructor != null) {
          var redirectedConstructorBase = redirectedConstructor.declaration;
          callback(redirectedConstructorBase);
          return;
        } else if (constant.isFactory) {
          // Factory constructor, but getConstRedirectedConstructor returned
          // null.  This can happen if we're visiting one of the special
          // external const factory constructors in the SDK, or if the code
          // contains errors (such as delegating to a non-const constructor, or
          // delegating to a constructor that can't be resolved).  In any of
          // these cases, we'll evaluate calls to this constructor without
          // having to refer to any other constants.  So we don't need to report
          // any dependencies.
          return;
        }
        bool defaultSuperInvocationNeeded = true;
        var initializers = constant.constantInitializers;
        for (ConstructorInitializer initializer in initializers) {
          if (initializer is SuperConstructorInvocation ||
              initializer is RedirectingConstructorInvocation) {
            defaultSuperInvocationNeeded = false;
          }
          initializer.accept(referenceFinder);
        }
        if (defaultSuperInvocationNeeded) {
          // No explicit superconstructor invocation found, so we need to
          // manually insert a reference to the implicit superconstructor.
          var superclass = constant.returnType.superclass;
          if (superclass != null && !superclass.isDartCoreObject) {
            var unnamedConstructor =
                superclass.element.unnamedConstructor?.declaration;
            if (unnamedConstructor != null && unnamedConstructor.isConst) {
              callback(unnamedConstructor);
            }
          }
        }
        for (FieldElement field in constant.enclosingElement.fields) {
          // Note: non-static const isn't allowed but we handle it anyway so
          // that we won't be confused by incorrect code.
          if ((field.isFinal || field.isConst) &&
              !field.isStatic &&
              field.hasInitializer) {
            callback(field);
          }
        }
        for (ParameterElement parameterElement in constant.parameters) {
          callback(parameterElement);
        }
      }
    } else if (constant is ElementAnnotationImpl) {
      Annotation constNode = constant.annotationAst;
      var element = constant.element;
      if (element is PropertyAccessorElement) {
        // The annotation is a reference to a compile-time constant variable,
        // so it depends on the variable.
        callback(element.variable.declaration);
      } else if (element is ConstructorElement) {
        // The annotation is a constructor invocation, so it depends on the
        // constructor.
        callback(element.declaration);
      } else {
        // This could happen in the event of invalid code.  The error will be
        // reported at constant evaluation time.
      }
      if (constNode.arguments != null) {
        constNode.arguments!.accept(referenceFinder);
      }
    } else if (constant is VariableElement) {
      // constant is a VariableElement but not a VariableElementImpl.  This can
      // happen sometimes in the case of invalid user code (for example, a
      // constant expression that refers to a non-static field inside a generic
      // class will wind up referring to a FieldMember).  So just don't bother
      // computing any dependencies.
    } else {
      // Should not happen.
      assert(false);
      AnalysisEngine.instance.instrumentationService
          .logError("Constant value computer trying to compute "
              "the value of a node of type ${constant.runtimeType}");
    }
  }

  Constant evaluateConstructorCall(
    LibraryElementImpl library,
    AstNode node,
    List<DartType>? typeArguments,
    List<Expression> arguments,
    ConstructorElement constructor,
    ConstantVisitor constantVisitor,
    ErrorReporter errorReporter, {
    ConstructorInvocation? invocation,
  }) {
    return _InstanceCreationEvaluator.evaluate(
      this,
      _declaredVariables,
      errorReporter,
      library,
      node,
      constructor,
      typeArguments,
      arguments,
      constantVisitor,
      isNullSafe: _isNonNullableByDefault,
      invocation: invocation,
    );
  }

  /// Generate an error indicating that the given [constant] is not a valid
  /// compile-time constant because it references at least one of the constants
  /// in the given [cycle], each of which directly or indirectly references the
  /// constant.
  void generateCycleError(
    Iterable<ConstantEvaluationTarget> cycle,
    ConstantEvaluationTarget constant,
  ) {
    if (constant is VariableElement) {
      RecordingErrorListener errorListener = RecordingErrorListener();
      ErrorReporter errorReporter = ErrorReporter(
        errorListener,
        constant.source!,
        isNonNullableByDefault: constant.library!.isNonNullableByDefault,
      );
      // TODO(paulberry): It would be really nice if we could extract enough
      // information from the 'cycle' argument to provide the user with a
      // description of the cycle.
      errorReporter.reportErrorForElement(
          CompileTimeErrorCode.RECURSIVE_COMPILE_TIME_CONSTANT, constant, []);
      (constant as VariableElementImpl).evaluationResult =
          EvaluationResultImpl(null, errorListener.errors);
    } else if (constant is ConstructorElement) {
      // We don't report cycle errors on constructor declarations since there
      // is nowhere to put the error information.
    } else {
      // Should not happen.  Formal parameter defaults and annotations should
      // never appear as part of a cycle because they can't be referred to.
      assert(false);
      AnalysisEngine.instance.instrumentationService
          .logError("Constant value computer trying to report a cycle error "
              "for a node of type ${constant.runtimeType}");
    }
  }

  /// If [constructor] redirects to another const constructor, return the
  /// const constructor it redirects to.  Otherwise return `null`.
  static ConstructorElement? getConstRedirectedConstructor(
      ConstructorElement constructor) {
    if (!constructor.isFactory) {
      return null;
    }
    var typeProvider = constructor.library.typeProvider;
    if (constructor.enclosingElement == typeProvider.symbolElement) {
      // The dart:core.Symbol has a const factory constructor that redirects
      // to dart:_internal.Symbol.  That in turn redirects to an external
      // const constructor, which we won't be able to evaluate.
      // So stop following the chain of redirections at dart:core.Symbol, and
      // let [evaluateInstanceCreationExpression] handle it specially.
      return null;
    }
    var redirectedConstructor = constructor.redirectedConstructor;
    if (redirectedConstructor == null) {
      // This can happen if constructor is an external factory constructor.
      return null;
    }
    if (!redirectedConstructor.isConst) {
      // Delegating to a non-const constructor--this is not allowed (and
      // is checked elsewhere--see
      // [ErrorVerifier.checkForRedirectToNonConstConstructor()]).
      return null;
    }
    return redirectedConstructor;
  }

  static _EnumConstant? _enumConstant(VariableElementImpl element) {
    if (element is ConstFieldElementImpl && element.isEnumConstant) {
      var enum_ = element.enclosingElement;
      if (enum_ is EnumElementImpl) {
        var index = enum_.constants.indexOf(element);
        assert(index >= 0);
        return _EnumConstant(
          index: index,
          name: element.name,
        );
      }
    }
    return null;
  }

  static DartObjectImpl _nullObject(LibraryElementImpl library) {
    return DartObjectImpl(
      library.typeSystem,
      library.typeProvider.nullType,
      NullState.NULL_STATE,
    );
  }

  /// Returns the representation of a constant expression which has an
  /// [InvalidType], with the given [defaultType].
  static DartObjectImpl _unresolvedObject(
      LibraryElementImpl library, DartType defaultType) {
    // TODO(kallentu): Use a better representation of an unresolved object that
    // doesn't need to rely on NullState.
    return DartObjectImpl(
      library.typeSystem,
      defaultType,
      NullState(isInvalid: true),
    );
  }
}

/// Interface for [AnalysisTarget]s for which constant evaluation can be
/// performed.
abstract class ConstantEvaluationTarget extends AnalysisTarget {
  /// Return the [AnalysisContext] which should be used to evaluate this
  /// constant.
  AnalysisContext get context;

  /// Return whether this constant is evaluated.
  bool get isConstantEvaluated;

  /// The library with this constant.
  LibraryElement? get library;
}

/// A visitor used to evaluate constant expressions to produce their
/// compile-time value.
class ConstantVisitor extends UnifyingAstVisitor<Constant> {
  /// The evaluation engine used to access the feature set, type system, and
  /// type provider.
  final ConstantEvaluationEngine evaluationEngine;

  /// The library that contains the constant expression being evaluated.
  final LibraryElementImpl _library;

  /// A mapping of variable names to runtime values.
  final Map<String, DartObjectImpl>? _lexicalEnvironment;

  /// A mapping of type parameter names to runtime values (types).
  final Map<TypeParameterElement, DartType>? _lexicalTypeEnvironment;

  final Substitution? _substitution;

  /// Error reporter that we use to report errors accumulated while computing
  /// the constant.
  final ErrorReporter _errorReporter;

  /// Helper class used to compute constant values.
  late final DartObjectComputer _dartObjectComputer;

  /// Initialize a newly created constant visitor. The [evaluationEngine] is
  /// used to evaluate instance creation expressions. The [lexicalEnvironment]
  /// is a map containing values which should override identifiers, or `null` if
  /// no overriding is necessary. The [_errorReporter] is used to report errors
  /// found during evaluation.  The [validator] is used by unit tests to verify
  /// correct dependency analysis.
  ///
  /// The [substitution] is specified for instance creations.
  ConstantVisitor(
    this.evaluationEngine,
    this._library,
    this._errorReporter, {
    Map<String, DartObjectImpl>? lexicalEnvironment,
    Map<TypeParameterElement, DartType>? lexicalTypeEnvironment,
    Substitution? substitution,
  })  : _lexicalEnvironment = lexicalEnvironment,
        _lexicalTypeEnvironment = lexicalTypeEnvironment,
        _substitution = substitution {
    _dartObjectComputer = DartObjectComputer(
      typeSystem,
      _library.featureSet,
      _errorReporter,
    );
  }

  /// Convenience getter to gain access to the [evaluationEngine]'s type system.
  TypeSystemImpl get typeSystem => _library.typeSystem;

  bool get _isNonNullableByDefault => typeSystem.isNonNullableByDefault;

  /// Convenience getter to gain access to the [evaluationEngine]'s type
  /// provider.
  TypeProvider get _typeProvider => _library.typeProvider;

  @override
  Constant visitAdjacentStrings(AdjacentStrings node) {
    return _concatenateNodes(node, node.strings);
  }

  @override
  Constant visitAsExpression(AsExpression node) {
    var expression = _getConstant(node.expression);
    if (expression is! DartObjectImpl) {
      return expression;
    }
    var type = _getConstant(node.type);
    if (type is! DartObjectImpl) {
      return type;
    }
    return _dartObjectComputer.castToType(node, expression, type);
  }

  @override
  Constant visitBinaryExpression(BinaryExpression node) {
    if (node.staticElement?.enclosingElement is ExtensionElement) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD, node);
      return InvalidConstant(
          node, CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD);
    }

    TokenType operatorType = node.operator.type;
    var leftResult = _getConstant(node.leftOperand);
    if (leftResult is! DartObjectImpl) {
      return leftResult;
    }

    // Used for the [DartObjectComputer], which will handle any exceptions.
    DartObjectImpl rightOperandComputer() {
      var constant = _getConstant(node.rightOperand);
      switch (constant) {
        case DartObjectImpl():
          return constant;
        case InvalidConstant():
          throw EvaluationException(constant.errorCode);
        default:
          throw EvaluationException(CompileTimeErrorCode.INVALID_CONSTANT);
      }
    }

    // Evaluate lazy operators.
    if (operatorType == TokenType.AMPERSAND_AMPERSAND) {
      if (leftResult.toBoolValue() == false) {
        var error = _reportNotPotentialConstants(node.rightOperand);
        if (error is InvalidConstant) {
          return error;
        }
      }
      return _dartObjectComputer.lazyAnd(
          node, leftResult, rightOperandComputer);
    } else if (operatorType == TokenType.BAR_BAR) {
      if (leftResult.toBoolValue() == true) {
        var error = _reportNotPotentialConstants(node.rightOperand);
        if (error is InvalidConstant) {
          return error;
        }
      }
      return _dartObjectComputer.lazyOr(node, leftResult, rightOperandComputer);
    } else if (operatorType == TokenType.QUESTION_QUESTION) {
      if (leftResult.isNull != true) {
        var error = _reportNotPotentialConstants(node.rightOperand);
        if (error is InvalidConstant) {
          return error;
        }
      }
      return _dartObjectComputer.lazyQuestionQuestion(
          node, leftResult, () => _getConstant(node.rightOperand));
    }

    // Evaluate eager operators.
    var rightResult = _getConstant(node.rightOperand);
    if (rightResult is! DartObjectImpl) {
      return rightResult;
    }
    if (operatorType == TokenType.AMPERSAND) {
      return _dartObjectComputer.eagerAnd(node, leftResult, rightResult);
    } else if (operatorType == TokenType.BANG_EQ) {
      return _dartObjectComputer.notEqual(node, leftResult, rightResult);
    } else if (operatorType == TokenType.BAR) {
      return _dartObjectComputer.eagerOr(node, leftResult, rightResult);
    } else if (operatorType == TokenType.CARET) {
      return _dartObjectComputer.eagerXor(node, leftResult, rightResult);
    } else if (operatorType == TokenType.EQ_EQ) {
      return _dartObjectComputer.equalEqual(node, leftResult, rightResult);
    } else if (operatorType == TokenType.GT) {
      return _dartObjectComputer.greaterThan(node, leftResult, rightResult);
    } else if (operatorType == TokenType.GT_EQ) {
      return _dartObjectComputer.greaterThanOrEqual(
          node, leftResult, rightResult);
    } else if (operatorType == TokenType.GT_GT) {
      return _dartObjectComputer.shiftRight(node, leftResult, rightResult);
    } else if (operatorType == TokenType.GT_GT_GT) {
      return _dartObjectComputer.logicalShiftRight(
          node, leftResult, rightResult);
    } else if (operatorType == TokenType.LT) {
      return _dartObjectComputer.lessThan(node, leftResult, rightResult);
    } else if (operatorType == TokenType.LT_EQ) {
      return _dartObjectComputer.lessThanOrEqual(node, leftResult, rightResult);
    } else if (operatorType == TokenType.LT_LT) {
      return _dartObjectComputer.shiftLeft(node, leftResult, rightResult);
    } else if (operatorType == TokenType.MINUS) {
      return _dartObjectComputer.minus(node, leftResult, rightResult);
    } else if (operatorType == TokenType.PERCENT) {
      return _dartObjectComputer.remainder(node, leftResult, rightResult);
    } else if (operatorType == TokenType.PLUS) {
      return _dartObjectComputer.add(node, leftResult, rightResult);
    } else if (operatorType == TokenType.STAR) {
      return _dartObjectComputer.times(node, leftResult, rightResult);
    } else if (operatorType == TokenType.SLASH) {
      return _dartObjectComputer.divide(node, leftResult, rightResult);
    } else if (operatorType == TokenType.TILDE_SLASH) {
      return _dartObjectComputer.integerDivide(node, leftResult, rightResult);
    } else {
      // TODO(https://github.com/dart-lang/sdk/issues/47061): Use a specific
      // error code.
      _error(node, null);
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
  }

  @override
  Constant visitBooleanLiteral(BooleanLiteral node) {
    return DartObjectImpl(
      typeSystem,
      _typeProvider.boolType,
      BoolState.from(node.value),
    );
  }

  @override
  Constant visitConditionalExpression(ConditionalExpression node) {
    var condition = node.condition;
    var conditionConstant = _getConstant(condition);
    if (conditionConstant is! DartObjectImpl) {
      return conditionConstant;
    }

    if (!conditionConstant.isBool) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.CONST_EVAL_TYPE_BOOL, condition);
      return InvalidConstant(
          condition, CompileTimeErrorCode.CONST_EVAL_TYPE_BOOL);
    }
    conditionConstant = _dartObjectComputer.applyBooleanConversion(
        condition, conditionConstant);
    if (conditionConstant is! DartObjectImpl) {
      return conditionConstant;
    }

    var conditionResultBool = conditionConstant.toBoolValue();
    if (conditionResultBool == true) {
      var error = _reportNotPotentialConstants(node.elseExpression);
      if (error is InvalidConstant) {
        return error;
      }
      return _getConstant(node.thenExpression);
    } else if (conditionResultBool == false) {
      var error = _reportNotPotentialConstants(node.thenExpression);
      if (error is InvalidConstant) {
        return error;
      }
      return _getConstant(node.elseExpression);
    } else {
      var thenConstant = _getConstant(node.thenExpression);
      if (thenConstant is InvalidConstant) {
        return thenConstant;
      }
      var elseConstant = _getConstant(node.elseExpression);
      if (elseConstant is InvalidConstant) {
        return elseConstant;
      }
      return DartObjectImpl.validWithUnknownValue(
        typeSystem,
        node.typeOrThrow,
      );
    }
  }

  @override
  Constant visitConstructorReference(ConstructorReference node) {
    var constructorFunctionType = node.typeOrThrow;
    if (constructorFunctionType is! FunctionType) {
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
    var classType = constructorFunctionType.returnType as InterfaceType;
    var typeArguments = classType.typeArguments;
    // The result is already instantiated during resolution;
    // [_dartObjectComputer.typeInstantiate] is unnecessary.
    var typeElement = node.constructorName.type.element as TypeDefiningElement;

    TypeAliasElement? viaTypeAlias;
    if (typeElement is TypeAliasElementImpl) {
      if (constructorFunctionType.typeFormals.isNotEmpty &&
          !typeElement.isProperRename) {
        // The type alias is not a proper rename of the aliased class, so
        // the constructor tear-off is distinct from the associated
        // constructor function of the aliased class.
        viaTypeAlias = typeElement;
      }
    }

    final constructorElement = node.constructorName.staticElement?.declaration
        .ifTypeOrNull<ConstructorElementImpl>();
    if (constructorElement == null) {
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }

    return DartObjectImpl(
      typeSystem,
      node.typeOrThrow,
      FunctionState(constructorElement,
          typeArguments: typeArguments, viaTypeAlias: viaTypeAlias),
    );
  }

  @override
  Constant visitDoubleLiteral(DoubleLiteral node) {
    return DartObjectImpl(
      typeSystem,
      _typeProvider.doubleType,
      DoubleState(node.value),
    );
  }

  @override
  Constant visitFunctionReference(FunctionReference node) {
    var functionResult = _getConstant(node.function);
    if (functionResult is! DartObjectImpl) {
      return functionResult;
    }

    // Report an error if any of the _inferred_ type argument types refer to a
    // type parameter. If, however, `node.typeArguments` is not `null`, then
    // any type parameters contained therein are reported as non-constant in
    // [ConstantVerifier].
    if (node.typeArguments == null) {
      var typeArgumentTypes = node.typeArgumentTypes;
      if (typeArgumentTypes != null) {
        var instantiatedTypeArgumentTypes = typeArgumentTypes.map((type) {
          if (type is TypeParameterType) {
            return _lexicalTypeEnvironment?[type.element] ?? type;
          } else {
            return type;
          }
        });
        if (instantiatedTypeArgumentTypes.any(hasTypeParameterReference)) {
          // TODO(kallentu): Don't report error here.
          _errorReporter.reportErrorForNode(
              CompileTimeErrorCode.CONST_WITH_TYPE_PARAMETERS_FUNCTION_TEAROFF,
              node);
          return InvalidConstant(node,
              CompileTimeErrorCode.CONST_WITH_TYPE_PARAMETERS_FUNCTION_TEAROFF);
        }
      }
    }

    var typeArgumentList = node.typeArguments;
    if (typeArgumentList == null) {
      return _instantiateFunctionType(node, functionResult);
    }

    var typeArguments = <DartType>[];
    for (var typeArgument in typeArgumentList.arguments) {
      var object = _getConstant(typeArgument);
      if (object is! DartObjectImpl) {
        return object;
      }
      var typeArgumentType = object.toTypeValue();
      if (typeArgumentType == null) {
        return InvalidConstant(
            typeArgument, CompileTimeErrorCode.INVALID_CONSTANT);
      }
      // TODO(srawlins): Test type alias types (`typedef i = int`) used as
      // type arguments. Possibly change implementation based on
      // canonicalization rules.
      typeArguments.add(typeArgumentType);
    }
    return _dartObjectComputer.typeInstantiate(
        functionResult, typeArguments, node.function);
  }

  @override
  Constant visitGenericFunctionType(GenericFunctionType node) {
    return DartObjectImpl(
      typeSystem,
      _typeProvider.typeType,
      TypeState(node.type),
    );
  }

  @override
  Constant visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst) {
      // TODO(https://github.com/dart-lang/sdk/issues/47061): Use a specific
      // error code.
      _error(node, null);
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
    var constructor = node.constructorName.staticElement;
    if (constructor == null) {
      // Couldn't resolve the constructor so we can't compute a value.  No
      // problem - the error has already been reported.
      // TODO(kallentu): Use a better error code for this.
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }

    return evaluationEngine.evaluateConstructorCall(
      _library,
      node,
      constructor.returnType.typeArguments,
      node.argumentList.arguments,
      constructor,
      this,
      _errorReporter,
    );
  }

  @override
  Constant visitIntegerLiteral(IntegerLiteral node) {
    if (node.staticType == _typeProvider.doubleType) {
      return DartObjectImpl(
        typeSystem,
        _typeProvider.doubleType,
        DoubleState(node.value?.toDouble()),
      );
    }
    return DartObjectImpl(
      typeSystem,
      _typeProvider.intType,
      IntState(node.value),
    );
  }

  @override
  Constant visitInterpolationExpression(InterpolationExpression node) {
    var result = _getConstant(node.expression);
    if (result is! DartObjectImpl) {
      return result;
    }

    if (!result.isBoolNumStringOrNull) {
      // TODO(kallentu): Don't report error here.
      _error(node, CompileTimeErrorCode.CONST_EVAL_TYPE_BOOL_NUM_STRING);
      return InvalidConstant(
          node, CompileTimeErrorCode.CONST_EVAL_TYPE_BOOL_NUM_STRING);
    }
    return _dartObjectComputer.performToString(node, result);
  }

  @override
  Constant visitInterpolationString(InterpolationString node) {
    return DartObjectImpl(
      typeSystem,
      _typeProvider.stringType,
      StringState(node.value),
    );
  }

  @override
  Constant visitIsExpression(IsExpression node) {
    var expression = _getConstant(node.expression);
    if (expression is! DartObjectImpl) {
      return expression;
    }
    var type = _getConstant(node.type);
    if (type is! DartObjectImpl) {
      return type;
    }
    return _dartObjectComputer.typeTest(node, expression, type);
  }

  @override
  Constant visitListLiteral(ListLiteral node) {
    if (!node.isConst) {
      // TODO(kallentu): Don't report the error here.
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.MISSING_CONST_IN_LIST_LITERAL, node);
      return InvalidConstant(
          node, CompileTimeErrorCode.MISSING_CONST_IN_LIST_LITERAL);
    }
    final elements = <DartObjectImpl>[];
    for (CollectionElement element in node.elements) {
      var result = _addElementsToList(elements, element);
      if (result is InvalidConstant) {
        return result;
      }
    }
    var nodeType = node.staticType;
    DartType elementType =
        nodeType is InterfaceType && nodeType.typeArguments.isNotEmpty
            ? nodeType.typeArguments[0]
            : _typeProvider.dynamicType;
    InterfaceType listType = _typeProvider.listType(elementType);
    return DartObjectImpl(
      typeSystem,
      listType,
      ListState(
        elementType: elementType,
        elements: elements,
      ),
    );
  }

  @override
  Constant visitMethodInvocation(MethodInvocation node) {
    var element = node.methodName.staticElement;
    if (element is FunctionElement) {
      if (element.name == "identical") {
        NodeList<Expression> arguments = node.argumentList.arguments;
        if (arguments.length == 2) {
          var enclosingElement = element.enclosingElement;
          if (enclosingElement is CompilationUnitElement) {
            LibraryElement library = enclosingElement.library;
            if (library.isDartCore) {
              var leftArgument = _getConstant(arguments[0]);
              if (leftArgument is! DartObjectImpl) {
                return leftArgument;
              }
              var rightArgument = _getConstant(arguments[1]);
              if (rightArgument is! DartObjectImpl) {
                return rightArgument;
              }
              return _dartObjectComputer.isIdentical(
                  node, leftArgument, rightArgument);
            }
          }
        }
      }
    }

    // Some methods aren't resolved by the time we are evaluating it. We'll mark
    // it and return immediately.
    if (node.staticType is InvalidType) {
      // TODO(kallentu): This error reporting retains the same behaviour as
      // before. Move this error reporting elsewhere.
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.INVALID_CONSTANT, node);
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT,
          isUnresolved: true);
    }

    // TODO(kallentu): Don't report error here.
    _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.CONST_EVAL_METHOD_INVOCATION, node);
    return InvalidConstant(
        node, CompileTimeErrorCode.CONST_EVAL_METHOD_INVOCATION);
  }

  @override
  Constant visitNamedExpression(NamedExpression node) =>
      _getConstant(node.expression);

  @override
  Constant visitNamedType(NamedType node) {
    var type = node.typeOrThrow;

    if ((!_isNonNullableByDefault || node.isTypeLiteralInConstantPattern) &&
        hasTypeParameterReference(type)) {
      // TODO(kallentu): Don't report error here and report a more specific
      // diagnostic
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.INVALID_CONSTANT, node);
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    } else if (node.isDeferred) {
      return _getDeferredLibraryError(node, node.name2) ??
          InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }

    if (_substitution != null) {
      type = _substitution!.substituteType(type);
    }

    return _getConstantValue(
      errorNode: node,
      expression: null,
      identifier: null,
      element: node.element,
      givenType: type,
    );
  }

  @override
  Constant? visitNode(AstNode node) {
    // TODO(https://github.com/dart-lang/sdk/issues/47061): Use a specific
    // error code.
    _error(node, null);
    return null;
  }

  @override
  Constant visitNullLiteral(NullLiteral node) {
    return ConstantEvaluationEngine._nullObject(_library);
  }

  @override
  Constant visitParenthesizedExpression(ParenthesizedExpression node) =>
      _getConstant(node.expression);

  @override
  Constant visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefixNode = node.prefix;
    final prefixElement = prefixNode.staticElement;

    // importPrefix.CONST
    if (prefixElement is PrefixElement) {
      if (node.isDeferred) {
        return _getDeferredLibraryError(node, node.identifier) ??
            InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
      }
    } else if (prefixElement is! ExtensionElement) {
      final prefixResult = _getConstant(prefixNode);
      if (prefixResult is! DartObjectImpl) {
        return prefixResult;
      }

      // String.length
      if (prefixElement is! InterfaceElement) {
        final stringLengthResult =
            _evaluateStringLength(prefixResult, node.identifier, node);
        if (stringLengthResult != null) {
          return stringLengthResult;
        }
      }
    }

    // Validate prefixed identifier.
    return _getConstantValue(
      errorNode: node,
      expression: node,
      identifier: node.identifier,
      element: node.identifier.staticElement,
    );
  }

  @override
  Constant visitPrefixExpression(PrefixExpression node) {
    var operand = _getConstant(node.operand);
    if (operand is! DartObjectImpl) {
      return operand;
    }
    if (node.staticElement?.enclosingElement is ExtensionElement) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD, node);
      return InvalidConstant(
          node, CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD);
    }
    if (node.operator.type == TokenType.BANG) {
      return _dartObjectComputer.logicalNot(node, operand);
    } else if (node.operator.type == TokenType.TILDE) {
      return _dartObjectComputer.bitNot(node, operand);
    } else if (node.operator.type == TokenType.MINUS) {
      return _dartObjectComputer.negated(node, operand);
    } else {
      // TODO(https://github.com/dart-lang/sdk/issues/47061): Use a specific
      // error code.
      _error(node, null);
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
  }

  @override
  Constant visitPropertyAccess(PropertyAccess node) {
    var target = node.target;
    if (target != null) {
      final prefixResult = _getConstant(target);
      if (prefixResult is! DartObjectImpl) {
        return prefixResult;
      }

      final stringLengthResult =
          _evaluateStringLength(prefixResult, node.propertyName, node);
      if (stringLengthResult != null) {
        return stringLengthResult;
      }
    }
    return _getConstantValue(
      errorNode: node,
      expression: node,
      identifier: node.propertyName,
      element: node.propertyName.staticElement,
    );
  }

  @override
  Constant visitRecordLiteral(RecordLiteral node) {
    var positionalFields = <DartObjectImpl>[];
    var namedFields = <String, DartObjectImpl>{};
    for (var field in node.fields) {
      if (field is NamedExpression) {
        var name = field.name.label.name;
        var value = _getConstant(field.expression);
        if (value is! DartObjectImpl) {
          return value;
        }
        namedFields[name] = value;
      } else {
        var value = _getConstant(field);
        if (value is! DartObjectImpl) {
          return value;
        }
        positionalFields.add(value);
      }
    }

    final nodeType = RecordType(
      positional: positionalFields.map((e) => e.type).toList(),
      named: namedFields.map((name, value) => MapEntry(name, value.type)),
      nullabilitySuffix: NullabilitySuffix.none,
    );

    return DartObjectImpl(
        typeSystem, nodeType, RecordState(positionalFields, namedFields));
  }

  @override
  Constant visitSetOrMapLiteral(SetOrMapLiteral node) {
    // Note: due to dartbug.com/33441, it's possible that a set/map literal
    // resynthesized from a summary will have neither its `isSet` or `isMap`
    // boolean set to `true`.  We work around the problem by assuming such
    // literals are maps.
    // TODO(paulberry): when dartbug.com/33441 is fixed, add an assertion here
    // to verify that `node.isSet == !node.isMap`.
    bool isMap = !node.isSet;
    if (isMap) {
      if (!node.isConst) {
        // TODO(kallentu): Don't report error here.
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.MISSING_CONST_IN_MAP_LITERAL, node);
        return InvalidConstant(
            node, CompileTimeErrorCode.MISSING_CONST_IN_MAP_LITERAL);
      }
      Map<DartObjectImpl, DartObjectImpl> map = {};
      for (CollectionElement element in node.elements) {
        var result = _addElementsToMap(map, element);
        if (result is InvalidConstant) {
          return result;
        }
      }
      DartType keyType = _typeProvider.dynamicType;
      DartType valueType = _typeProvider.dynamicType;
      var nodeType = node.staticType;
      if (nodeType is InterfaceType) {
        var typeArguments = nodeType.typeArguments;
        if (typeArguments.length >= 2) {
          keyType = typeArguments[0];
          valueType = typeArguments[1];
        }
      }
      InterfaceType mapType = _typeProvider.mapType(keyType, valueType);
      return DartObjectImpl(typeSystem, mapType, MapState(map));
    } else {
      if (!node.isConst) {
        // TODO(kallentu): Don't report error here.
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.MISSING_CONST_IN_SET_LITERAL, node);
        return InvalidConstant(
            node, CompileTimeErrorCode.MISSING_CONST_IN_SET_LITERAL);
      }
      Set<DartObjectImpl> set = <DartObjectImpl>{};
      for (CollectionElement element in node.elements) {
        var result = _addElementsToSet(set, element);
        if (result is InvalidConstant) {
          return result;
        }
      }
      var nodeType = node.staticType;
      DartType elementType =
          nodeType is InterfaceType && nodeType.typeArguments.isNotEmpty
              ? nodeType.typeArguments[0]
              : _typeProvider.dynamicType;
      InterfaceType setType = _typeProvider.setType(elementType);
      return DartObjectImpl(typeSystem, setType, SetState(set));
    }
  }

  @override
  Constant visitSimpleIdentifier(SimpleIdentifier node) {
    var value = _lexicalEnvironment?[node.name];
    if (value != null) {
      return _instantiateFunctionTypeForSimpleIdentifier(node, value);
    }

    return _getConstantValue(
      errorNode: node,
      expression: node,
      identifier: node,
      element: node.staticElement,
    );
  }

  @override
  Constant visitSimpleStringLiteral(SimpleStringLiteral node) {
    return DartObjectImpl(
      typeSystem,
      _typeProvider.stringType,
      StringState(node.value),
    );
  }

  @override
  Constant visitStringInterpolation(StringInterpolation node) {
    return _concatenateNodes(node, node.elements);
  }

  @override
  Constant visitSymbolLiteral(SymbolLiteral node) {
    StringBuffer buffer = StringBuffer();
    List<Token> components = node.components;
    for (int i = 0; i < components.length; i++) {
      if (i > 0) {
        buffer.writeCharCode(0x2E);
      }
      buffer.write(components[i].lexeme);
    }
    return DartObjectImpl(
      typeSystem,
      _typeProvider.symbolType,
      SymbolState(buffer.toString()),
    );
  }

  @override
  Constant visitTypeLiteral(TypeLiteral node) => _getConstant(node.type);

  /// Add the entries produced by evaluating the given collection [element] to
  /// the given [list]. Return an [InvalidConstant] if the evaluation of one or
  /// more of the elements failed.
  InvalidConstant? _addElementsToList(
      List<DartObject> list, CollectionElement element) {
    switch (element) {
      case Expression():
        var expression = _getConstant(element);
        switch (expression) {
          case InvalidConstant():
            return expression;
          case DartObjectImpl():
            list.add(expression);
            return null;
        }
      case ForElement():
        // TODO(kallentu): Don't report error here.
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT, element);
        return InvalidConstant(
            element, CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT);
      case IfElement():
        var condition = _getConstant(element.expression);
        switch (condition) {
          case InvalidConstant():
            return condition;
          case DartObjectImpl():
            var conditionValue = condition.toBoolValue();
            if (conditionValue == null) {
              // TODO(kallentu): Don't report error here.
              _errorReporter.reportErrorForNode(
                  CompileTimeErrorCode.NON_BOOL_CONDITION, element.expression);
              return InvalidConstant(
                  element.expression, CompileTimeErrorCode.NON_BOOL_CONDITION);
            } else if (conditionValue) {
              return _addElementsToList(list, element.thenElement);
            } else if (element.elseElement != null) {
              return _addElementsToList(list, element.elseElement!);
            }
            // There's no else element, but the condition value is false.
            return null;
        }
      case MapLiteralEntry():
        return InvalidConstant(element, CompileTimeErrorCode.INVALID_CONSTANT);
      case SpreadElement():
        var spread = _getConstant(element.expression);
        switch (spread) {
          case InvalidConstant():
            return spread;
          case DartObjectImpl():
            var listValue = spread.toListValue();
            if (listValue == null) {
              return InvalidConstant(element.expression,
                  CompileTimeErrorCode.CONST_SPREAD_EXPECTED_LIST_OR_SET);
            }
            list.addAll(listValue);
            return null;
        }
    }
  }

  /// Add the entries produced by evaluating the given map [element] to the
  /// given [map]. Return an [InvalidConstant] if the evaluation of one or
  /// more of the elements failed.
  InvalidConstant? _addElementsToMap(
      Map<DartObjectImpl, DartObjectImpl> map, CollectionElement element) {
    switch (element) {
      case Expression():
        return InvalidConstant(element, CompileTimeErrorCode.INVALID_CONSTANT);
      case ForElement():
        // TODO(kallentu): Don't report error here.
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT, element);
        return InvalidConstant(
            element, CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT);
      case IfElement():
        var condition = _getConstant(element.expression);
        switch (condition) {
          case InvalidConstant():
            return condition;
          case DartObjectImpl():
            var conditionValue = condition.toBoolValue();
            if (conditionValue == null) {
              // TODO(kallentu): Don't report error here.
              _errorReporter.reportErrorForNode(
                  CompileTimeErrorCode.NON_BOOL_CONDITION, element.expression);
              return InvalidConstant(
                  element.expression, CompileTimeErrorCode.NON_BOOL_CONDITION);
            } else if (conditionValue) {
              return _addElementsToMap(map, element.thenElement);
            } else if (element.elseElement != null) {
              return _addElementsToMap(map, element.elseElement!);
            }
            // There's no else element, but the condition value is false.
            return null;
        }
      case MapLiteralEntry():
        var keyResult = _getConstant(element.key);
        var valueResult = _getConstant(element.value);
        switch (keyResult) {
          case InvalidConstant():
            return keyResult;
          case DartObjectImpl():
            switch (valueResult) {
              case InvalidConstant():
                return valueResult;
              case DartObjectImpl():
                map[keyResult] = valueResult;
            }
        }
        return null;
      case SpreadElement():
        var spread = _getConstant(element.expression);
        switch (spread) {
          case InvalidConstant():
            return spread;
          case DartObjectImpl():
            var mapValue = spread.toMapValue();
            if (mapValue == null) {
              return InvalidConstant(element.expression,
                  CompileTimeErrorCode.CONST_SPREAD_EXPECTED_MAP);
            }
            map.addAll(mapValue);
            return null;
        }
    }
  }

  /// Add the entries produced by evaluating the given collection [element] to
  /// the given [set]. Return an [InvalidConstant] if the evaluation of one or
  /// more of the elements failed.
  InvalidConstant? _addElementsToSet(
      Set<DartObject> set, CollectionElement element) {
    switch (element) {
      case Expression():
        var expression = _getConstant(element);
        switch (expression) {
          case InvalidConstant():
            return expression;
          case DartObjectImpl():
            set.add(expression);
            return null;
        }
      case ForElement():
        // TODO(kallentu): Don't report error here.
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT, element);
        return InvalidConstant(
            element, CompileTimeErrorCode.CONST_EVAL_FOR_ELEMENT);
      case IfElement():
        var condition = _getConstant(element.expression);
        switch (condition) {
          case InvalidConstant():
            return condition;
          case DartObjectImpl():
            var conditionValue = condition.toBoolValue();
            if (conditionValue == null) {
              // TODO(kallentu): Don't report error here.
              _errorReporter.reportErrorForNode(
                  CompileTimeErrorCode.NON_BOOL_CONDITION, element.expression);
              return InvalidConstant(
                  element.expression, CompileTimeErrorCode.NON_BOOL_CONDITION);
            } else if (conditionValue) {
              return _addElementsToSet(set, element.thenElement);
            } else if (element.elseElement != null) {
              return _addElementsToSet(set, element.elseElement!);
            }
            // There's no else element, but the condition value is false.
            return null;
        }
      case MapLiteralEntry():
        return InvalidConstant(element, CompileTimeErrorCode.INVALID_CONSTANT);
      case SpreadElement():
        var spread = _getConstant(element.expression);
        switch (spread) {
          case InvalidConstant():
            return spread;
          case DartObjectImpl():
            var setValue = spread.toSetValue();
            if (setValue == null) {
              return InvalidConstant(element.expression,
                  CompileTimeErrorCode.CONST_SPREAD_EXPECTED_LIST_OR_SET);
            }
            set.addAll(setValue);
            return null;
        }
    }
  }

  /// Returns the result of concatenating [astNodes].
  ///
  /// If there's an [InvalidConstant] found, it will return early.
  Constant _concatenateNodes(Expression node, List<AstNode> astNodes) {
    Constant? result;
    for (AstNode astNode in astNodes) {
      var constant = _getConstant(astNode);
      if (constant is! DartObjectImpl) {
        return constant;
      }

      if (result == null) {
        result = constant;
      } else if (result is DartObjectImpl) {
        result = _dartObjectComputer.concatenate(node, result, constant);
        if (result is InvalidConstant) {
          return result;
        }
      }
    }

    if (result == null) {
      // No errors have been detected, but we did not concatenate any nodes.
      return DartObjectImpl(
        typeSystem,
        _typeProvider.stringType,
        StringState.UNKNOWN_VALUE,
      );
    }
    return result;
  }

  /// Create an error associated with the given [node]. The error will have the
  /// given error [code].
  void _error(AstNode node, ErrorCode? code) {
    if (code == null) {
      var parent = node.parent;
      var parent2 = parent?.parent;
      if (parent is ArgumentList &&
          parent2 is InstanceCreationExpression &&
          parent2.isConst) {
        code = CompileTimeErrorCode.CONST_WITH_NON_CONSTANT_ARGUMENT;
      } else {
        code = CompileTimeErrorCode.INVALID_CONSTANT;
      }
    }
    _errorReporter.reportErrorForNode(code, node);
  }

  /// Attempt to evaluate a constant that reads the length of a `String`.
  ///
  /// Return a valid [DartObjectImpl] if the given [targetResult] represents a
  /// `String` and the [identifier] is `length`, an [InvalidConstant] if there's
  /// an error, and `null` otherwise.
  Constant? _evaluateStringLength(DartObjectImpl targetResult,
      SimpleIdentifier identifier, AstNode errorNode) {
    if (identifier.staticElement?.enclosingElement is ExtensionElement) {
      _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD, errorNode);
      return InvalidConstant(
          errorNode, CompileTimeErrorCode.CONST_EVAL_EXTENSION_METHOD);
    }

    if (identifier.name == 'length') {
      final targetType = targetResult.type;
      if (!(targetType is InterfaceType && targetType.isDartCoreString)) {
        _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.CONST_EVAL_PROPERTY_ACCESS,
            errorNode,
            [identifier.name, targetType]);
        return InvalidConstant(
            errorNode, CompileTimeErrorCode.CONST_EVAL_PROPERTY_ACCESS,
            arguments: [identifier.name, targetType]);
      }
      return _dartObjectComputer.stringLength(errorNode, targetResult);
    }

    // TODO(kallentu): Make a more specific error here if we aren't accessing
    // the '.length' property.
    return null;
  }

  /// Return a [Constant], evaluated by the [ConstantVisitor].
  ///
  /// The [ConstantVisitor] shouldn't return any `null` values even though
  /// [UnifyingAstVisitor] allows it. If we encounter an unexpected `null`
  /// value, we will return an [InvalidConstant] instead.
  Constant _getConstant(AstNode node) {
    final result = node.accept(this);
    if (result == null) {
      // Should never reach this.
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
    return result;
  }

  /// Returns a [Constant] based on the [element] provided.
  ///
  /// The [errorNode] is the node to be used if an error needs to be reported,
  /// the [expression] is used to identify type parameter errors, and
  /// [identifier] to determine the constant of any [ExecutableElement]s.
  ///
  /// TODO(kallentu): Revisit this method and clean it up a bit.
  Constant _getConstantValue({
    required AstNode errorNode,
    required Expression? expression,
    required SimpleIdentifier? identifier,
    required Element? element,
    DartType? givenType,
  }) {
    final errorNode2 = evaluationEngine.configuration.errorNode(errorNode);
    element = element?.declaration;
    final variableElement =
        element is PropertyAccessorElement ? element.variable : element;

    // TODO(srawlins): Remove this check when [FunctionReference]s are inserted
    // for generic function instantiation for pre-constructor-references code.
    if (expression is SimpleIdentifier &&
        (expression.tearOffTypeArgumentTypes?.any(hasTypeParameterReference) ??
            false)) {
      // TODO(kallentu): Don't report error here.
      _error(expression, null);
      return InvalidConstant(expression, CompileTimeErrorCode.INVALID_CONSTANT);
    }

    if (variableElement is VariableElementImpl) {
      // We access values of constant variables here in two cases: when we
      // compute values of other constant variables, or when we compute values
      // and errors for other constant expressions. In either case we have
      // already computed values of all dependencies first (or detect a cycle),
      // so the value has already been computed and we can just return it.
      final result = variableElement.evaluationResult;
      final isConstField = variableElement is FieldElement &&
          (variableElement.isConst || variableElement.isFinal);
      if (isConstField || variableElement.isConst) {
        // The constant value isn't computed yet, or there is an error while
        // computing. We will mark it and determine whether or not to continue
        // the evaluation upstream.
        if (result == null) {
          _error(errorNode2, null);
          return InvalidConstant(
              errorNode, CompileTimeErrorCode.INVALID_CONSTANT,
              isUnresolved: true);
        }

        final value = result.value;
        if (value == null) {
          // TODO(kallentu): Investigate and fix the test failures that occur if
          // we report errors here.
          return InvalidConstant(
              errorNode, CompileTimeErrorCode.INVALID_CONSTANT,
              isUnresolved: true);
        } else if (identifier == null) {
          return InvalidConstant(
              errorNode, CompileTimeErrorCode.INVALID_CONSTANT);
        }

        return _instantiateFunctionTypeForSimpleIdentifier(identifier, value);
      }
    } else if (variableElement is ConstructorElementImpl &&
        expression != null) {
      return DartObjectImpl(
        typeSystem,
        expression.typeOrThrow,
        FunctionState(variableElement),
      );
    } else if (variableElement is ExecutableElementImpl) {
      if (variableElement.isStatic) {
        var rawType = DartObjectImpl(
          typeSystem,
          variableElement.type,
          FunctionState(variableElement),
        );
        if (identifier == null) {
          return InvalidConstant(
              errorNode, CompileTimeErrorCode.INVALID_CONSTANT);
        }
        return _instantiateFunctionTypeForSimpleIdentifier(identifier, rawType);
      }
    } else if (variableElement is InterfaceElement) {
      var type = givenType ??
          variableElement.instantiate(
            typeArguments: variableElement.typeParameters
                .map((t) => _typeProvider.dynamicType)
                .toFixedList(),
            nullabilitySuffix: NullabilitySuffix.star,
          );
      return DartObjectImpl(
        typeSystem,
        _typeProvider.typeType,
        TypeState(type),
      );
    } else if (variableElement is DynamicElementImpl) {
      return DartObjectImpl(
        typeSystem,
        _typeProvider.typeType,
        TypeState(_typeProvider.dynamicType),
      );
    } else if (variableElement is TypeAliasElement) {
      var type = givenType ??
          variableElement.instantiate(
            typeArguments: variableElement.typeParameters
                .map((t) => t.bound ?? _typeProvider.dynamicType)
                .toList(),
            nullabilitySuffix: NullabilitySuffix.star,
          );
      return DartObjectImpl(
        typeSystem,
        _typeProvider.typeType,
        TypeState(type),
      );
    } else if (variableElement is NeverElementImpl) {
      return DartObjectImpl(
        typeSystem,
        _typeProvider.typeType,
        TypeState(_typeProvider.neverType),
      );
    } else if (variableElement is TypeParameterElement) {
      // Constants may refer to type parameters only if the constructor-tearoffs
      // feature is enabled.
      if (_library.featureSet.isEnabled(Feature.constructor_tearoffs)) {
        var typeArgument = _lexicalTypeEnvironment?[variableElement];
        if (typeArgument != null) {
          return DartObjectImpl(
            typeSystem,
            _typeProvider.typeType,
            TypeState(typeArgument),
          );
        }
      }
    }

    // The expression is unresolved by the time we are evaluating it. We'll mark
    // it and return immediately.
    if (expression != null && expression.staticType is InvalidType) {
      // TODO(kallentu): This error reporting retains the same behaviour as
      // before. Move this error reporting elsewhere.
      _error(errorNode2, null);
      return InvalidConstant(errorNode, CompileTimeErrorCode.INVALID_CONSTANT,
          isUnresolved: true);
    }

    // TODO(https://github.com/dart-lang/sdk/issues/47061): Use a specific
    // error code.
    _error(errorNode2, null);
    return InvalidConstant(errorNode2, CompileTimeErrorCode.INVALID_CONSTANT);
  }

  InvalidConstant? _getDeferredLibraryError(
      AstNode node, SyntacticEntity errorTarget) {
    var errorCode = () {
      AstNode? previous;
      for (AstNode? current = node; current != null;) {
        if (current is Annotation) {
          return CompileTimeErrorCode
              .INVALID_ANNOTATION_CONSTANT_VALUE_FROM_DEFERRED_LIBRARY;
        } else if (current is ConstantContextForExpressionImpl) {
          return CompileTimeErrorCode
              .CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE_FROM_DEFERRED_LIBRARY;
        } else if (current is DefaultFormalParameter) {
          return CompileTimeErrorCode
              .NON_CONSTANT_DEFAULT_VALUE_FROM_DEFERRED_LIBRARY;
        } else if (current is IfElement && current.expression == node) {
          return CompileTimeErrorCode
              .IF_ELEMENT_CONDITION_FROM_DEFERRED_LIBRARY;
        } else if (current is InstanceCreationExpression) {
          return CompileTimeErrorCode
              .CONST_CONSTRUCTOR_CONSTANT_FROM_DEFERRED_LIBRARY;
        } else if (current is ListLiteral) {
          return CompileTimeErrorCode
              .NON_CONSTANT_LIST_ELEMENT_FROM_DEFERRED_LIBRARY;
        } else if (current is MapLiteralEntry) {
          if (previous == current.key) {
            return CompileTimeErrorCode
                .NON_CONSTANT_MAP_KEY_FROM_DEFERRED_LIBRARY;
          } else {
            return CompileTimeErrorCode
                .NON_CONSTANT_MAP_VALUE_FROM_DEFERRED_LIBRARY;
          }
        } else if (current is SetOrMapLiteral) {
          return CompileTimeErrorCode.SET_ELEMENT_FROM_DEFERRED_LIBRARY;
        } else if (current is SpreadElement) {
          return CompileTimeErrorCode.SPREAD_EXPRESSION_FROM_DEFERRED_LIBRARY;
        } else if (current is SwitchCase) {
          return CompileTimeErrorCode
              .NON_CONSTANT_CASE_EXPRESSION_FROM_DEFERRED_LIBRARY;
        } else if (current is SwitchPatternCase) {
          return CompileTimeErrorCode.PATTERN_CONSTANT_FROM_DEFERRED_LIBRARY;
        } else if (current is VariableDeclaration) {
          return CompileTimeErrorCode
              .CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE_FROM_DEFERRED_LIBRARY;
        }
        previous = current;
        current = current.parent;
      }
    }();
    if (errorCode != null) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForOffset(
        errorCode,
        errorTarget.offset,
        errorTarget.length,
      );
      return InvalidConstant(node, errorCode);
    }
    return null;
  }

  /// If the type of [value] is a generic [FunctionType], and [node] has type
  /// argument types, returns [value] type-instantiated with those [node]'s
  /// type argument types, otherwise returns [value].
  DartObjectImpl _instantiateFunctionType(
      FunctionReference node, DartObjectImpl value) {
    var functionElement = value.toFunctionValue();
    if (functionElement is! ExecutableElement) {
      return value;
    }
    var valueType = functionElement.type;
    if (valueType.typeFormals.isNotEmpty) {
      var typeArgumentTypes = node.typeArgumentTypes;
      if (typeArgumentTypes != null && typeArgumentTypes.isNotEmpty) {
        var instantiatedType =
            functionElement.type.instantiate(typeArgumentTypes);
        var substitution = _substitution;
        if (substitution != null) {
          instantiatedType =
              substitution.substituteType(instantiatedType) as FunctionType;
        }
        return value.typeInstantiate(
            typeSystem, instantiatedType, typeArgumentTypes);
      }
    }
    return value;
  }

  /// If the type of [value] is a generic [FunctionType], and [node] is a
  /// [SimpleIdentifier] with tear-off type argument types, returns [value]
  /// type-instantiated with those [node]'s tear-off type argument types,
  /// otherwise returns [value].
  Constant _instantiateFunctionTypeForSimpleIdentifier(
      SimpleIdentifier node, DartObjectImpl value) {
    // TODO(srawlins): When all code uses [FunctionReference]s generated via
    // generic function instantiation, remove this method and all call sites.
    var functionElement = value.toFunctionValue();
    if (functionElement is! ExecutableElement) {
      return value;
    }
    var valueType = functionElement.type;
    if (valueType.typeFormals.isNotEmpty) {
      var tearOffTypeArgumentTypes = node.tearOffTypeArgumentTypes;
      if (tearOffTypeArgumentTypes != null &&
          tearOffTypeArgumentTypes.isNotEmpty) {
        var instantiatedType =
            functionElement.type.instantiate(tearOffTypeArgumentTypes);
        return value.typeInstantiate(
            typeSystem, instantiatedType, tearOffTypeArgumentTypes);
      }
    }
    return value;
  }

  /// Returns the first not-potentially constant error found with [node] or
  /// `null` if there are none.
  InvalidConstant? _reportNotPotentialConstants(AstNode node) {
    var notPotentiallyConstants = getNotPotentiallyConstants(
      node,
      featureSet: _library.featureSet,
    );
    if (notPotentiallyConstants.isEmpty) return null;

    // TODO(kallentu): Don't report error here.
    // Only report the first invalid constant we see.
    _errorReporter.reportErrorForNode(
      CompileTimeErrorCode.INVALID_CONSTANT,
      notPotentiallyConstants.first,
    );
    return InvalidConstant(
        notPotentiallyConstants.first, CompileTimeErrorCode.INVALID_CONSTANT);
  }

  /// Return the value of the given [expression], or a representation of a fake
  /// constant to continue the evaluation if the expression is unresolved.
  Constant _valueOf(Expression expression, DartType defaultType) {
    final expressionValue = _getConstant(expression);
    switch (expressionValue) {
      case InvalidConstant(isUnresolved: true):
        return ConstantEvaluationEngine._unresolvedObject(
            _library, defaultType);
      case Constant():
        return expressionValue;
    }
  }
}

/// A utility class that contains methods for manipulating instances of a Dart
/// class and for collecting errors during evaluation.
class DartObjectComputer {
  final TypeSystemImpl _typeSystem;
  final FeatureSet _featureSet;

  /// The error reporter that we are using to collect errors.
  final ErrorReporter _errorReporter;

  DartObjectComputer(this._typeSystem, this._featureSet, this._errorReporter);

  Constant add(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.add(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  /// Return the result of applying boolean conversion to the
  /// [evaluationResult]. The [node] is the node against which errors should be
  /// reported.
  Constant applyBooleanConversion(
      AstNode node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.convertToBool(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant bitNot(Expression node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.bitNot(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant castToType(
      AsExpression node, DartObjectImpl expression, DartObjectImpl type) {
    try {
      return expression.castToType(_typeSystem, type);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant concatenate(Expression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.concatenate(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant divide(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.divide(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant eagerAnd(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.eagerAnd(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant eagerOr(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.eagerOr(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant eagerXor(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.eagerXor(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant equalEqual(Expression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.equalEqual(_typeSystem, _featureSet, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant greaterThan(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.greaterThan(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant greaterThanOrEqual(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.greaterThanOrEqual(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant integerDivide(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.integerDivide(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant isIdentical(Expression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.isIdentical2(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant lazyAnd(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl Function() rightOperandComputer) {
    try {
      return leftOperand.lazyAnd(_typeSystem, rightOperandComputer);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant lazyOr(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl Function() rightOperandComputer) {
    try {
      return leftOperand.lazyOr(_typeSystem, rightOperandComputer);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant lazyQuestionQuestion(Expression node, DartObjectImpl leftOperand,
      Constant Function() rightOperandComputer) {
    if (leftOperand.isNull) {
      return rightOperandComputer();
    }
    return leftOperand;
  }

  Constant lessThan(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.lessThan(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant lessThanOrEqual(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.lessThanOrEqual(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant logicalNot(Expression node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.logicalNot(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant logicalShiftRight(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.logicalShiftRight(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant minus(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.minus(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant negated(Expression node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.negated(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant notEqual(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.notEqual(_typeSystem, _featureSet, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant performToString(AstNode node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.performToString(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant remainder(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.remainder(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant shiftLeft(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.shiftLeft(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant shiftRight(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.shiftRight(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant stringLength(AstNode node, DartObjectImpl evaluationResult) {
    try {
      return evaluationResult.stringLength(_typeSystem);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant times(BinaryExpression node, DartObjectImpl leftOperand,
      DartObjectImpl rightOperand) {
    try {
      return leftOperand.times(_typeSystem, rightOperand);
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }

  Constant typeInstantiate(
    DartObjectImpl function,
    List<DartType> typeArguments,
    Expression node,
  ) {
    var rawType = function.type;
    if (rawType is FunctionType) {
      if (typeArguments.length != rawType.typeFormals.length) {
        return InvalidConstant(
            node, CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION);
      }
      var type = rawType.instantiate(typeArguments);
      return function.typeInstantiate(_typeSystem, type, typeArguments);
    } else {
      return InvalidConstant(node, CompileTimeErrorCode.INVALID_CONSTANT);
    }
  }

  Constant typeTest(
      IsExpression node, DartObjectImpl expression, DartObjectImpl type) {
    try {
      DartObjectImpl result = expression.hasType(_typeSystem, type);
      if (node.notOperator != null) {
        return result.logicalNot(_typeSystem);
      }
      return result;
    } on EvaluationException catch (exception) {
      // TODO(kallentu): Don't report error here.
      _errorReporter.reportErrorForNode(exception.errorCode, node);
      return InvalidConstant(node, exception.errorCode);
    }
  }
}

/// The result of attempting to evaluate an expression.
class EvaluationResult {
  // TODO(brianwilkerson) Merge with EvaluationResultImpl
  /// The value of the expression.
  final DartObject? value;

  /// The errors that should be reported for the expression(s) that were
  /// evaluated.
  final List<AnalysisError>? _errors;

  /// Initialize a newly created result object with the given [value] and set of
  /// [_errors]. Clients should use one of the factory methods: [forErrors] and
  /// [forValue].
  EvaluationResult(this.value, this._errors);

  /// Return a list containing the errors that should be reported for the
  /// expression(s) that were evaluated. If there are no such errors, the list
  /// will be empty. The list can be empty even if the expression is not a valid
  /// compile time constant if the errors would have been reported by other
  /// parts of the analysis engine.
  List<AnalysisError> get errors => _errors ?? AnalysisError.NO_ERRORS;

  /// Return `true` if the expression is a compile-time constant expression that
  /// would not throw an exception when evaluated.
  bool get isValid => _errors == null;

  /// Return an evaluation result representing the result of evaluating an
  /// expression that is not a compile-time constant because of the given
  /// [errors].
  static EvaluationResult forErrors(List<AnalysisError> errors) =>
      EvaluationResult(null, errors);

  /// Return an evaluation result representing the result of evaluating an
  /// expression that is a compile-time constant that evaluates to the given
  /// [value].
  static EvaluationResult forValue(DartObject value) =>
      EvaluationResult(value, null);
}

/// The result of attempting to evaluate a expression.
class EvaluationResultImpl {
  /// The errors encountered while trying to evaluate the compile time constant.
  /// These errors may or may not have prevented the expression from being a
  /// valid compile time constant.
  final List<AnalysisError> _errors;

  /// The value of the expression, or `null` if the value couldn't be computed
  /// due to errors.
  final DartObjectImpl? value;

  EvaluationResultImpl(
    this.value, [
    this._errors = const [],
  ]);

  List<AnalysisError> get errors => _errors;

  bool equalValues(TypeProvider typeProvider, EvaluationResultImpl result) {
    if (value != null) {
      if (result.value == null) {
        return false;
      }
      return value == result.value;
    } else {
      return false;
    }
  }

  @override
  String toString() {
    if (value == null) {
      return "error";
    }
    return value.toString();
  }
}

class _EnumConstant {
  final int index;
  final String name;

  _EnumConstant({
    required this.index,
    required this.name,
  });
}

/// The result of evaluation the initializers declared on a const constructor.
class _InitializersEvaluationResult {
  /// The result of a const evaluation of an initializer.
  ///
  /// If the evaluation of the const instance creation expression is incomplete,
  /// then [result] will be `null`.
  ///
  /// If a redirecting initializer which redirects to a const constructor was
  /// encountered, [result] is the result of evaluating that call.
  ///
  /// If an assert initializer is encountered, and the evaluation of this assert
  /// results in an error or a `false` value, [result] is an [InvalidConstant].
  final Constant? result;

  /// Whether evaluation of the const instance creation expression which led to
  /// evaluating constructor initializers is complete.
  ///
  /// If `true`, `result` should be used as the result of said const instance
  /// creation expression evaluation.
  final bool evaluationIsComplete;

  /// If a superinitializer was encountered, the name of the super constructor,
  /// otherwise `null`.
  final String? superName;

  /// If a superinitializer was encountered, the arguments passed to the super
  /// constructor, otherwise `null`.
  final List<Expression>? superArguments;

  _InitializersEvaluationResult(
    this.result, {
    required this.evaluationIsComplete,
    this.superName,
    this.superArguments,
  });
}

/// An evaluator which evaluates a const instance creation expression.
///
/// [_InstanceCreationEvaluator.evaluate] is the main entrypoint.
class _InstanceCreationEvaluator {
  /// Parameter to "fromEnvironment" methods that denotes the default value.
  static const String _defaultValueParam = 'defaultValue';

  /// Source of RegExp matching declarable operator names.
  /// From sdk/lib/internal/symbol.dart.
  static const String _operatorPattern =
      "(?:[\\-+*/%&|^]|\\[\\]=?|==|~/?|<[<=]?|>[>=]?|unary-)";

  /// Source of RegExp matching any public identifier.
  /// From sdk/lib/internal/symbol.dart.
  static const String _publicIdentifierPattern =
      "(?!$_reservedWordPattern\\b(?!\\\$))[a-zA-Z\$][\\w\$]*";

  /// RegExp that validates a non-empty non-private symbol.
  /// From sdk/lib/internal/symbol.dart.
  static final RegExp _publicSymbolPattern = RegExp('^(?:$_operatorPattern\$|'
      '$_publicIdentifierPattern(?:=?\$|[.](?!\$)))+?\$');

  /// Source of RegExp matching Dart reserved words.
  /// From sdk/lib/internal/symbol.dart.
  static const String _reservedWordPattern =
      "(?:assert|break|c(?:a(?:se|tch)|lass|on(?:st|tinue))|"
      "d(?:efault|o)|e(?:lse|num|xtends)|f(?:alse|inal(?:ly)?|or)|"
      "i[fns]|n(?:ew|ull)|ret(?:hrow|urn)|s(?:uper|witch)|t(?:h(?:is|row)|"
      "r(?:ue|y))|v(?:ar|oid)|w(?:hile|ith))";

  final ConstantEvaluationEngine _evaluationEngine;

  /// The set of variables declared on the command line using '-D'.
  final DeclaredVariables _declaredVariables;

  final LibraryElementImpl _library;

  final BooleanErrorListener _externalErrorListener = BooleanErrorListener();

  /// An error reporter for errors determined while computing values for field
  /// initializers, or default values for the constructor parameters.
  ///
  /// Such errors cannot be reported into [_errorReporter], because they usually
  /// happen in a different source. But they still should cause a constant
  /// evaluation error for the current node.
  late final ErrorReporter _externalErrorReporter = ErrorReporter(
    _externalErrorListener,
    _constructor.source,
    isNonNullableByDefault: _library.isNonNullableByDefault,
  );

  late final ConstantVisitor _initializerVisitor = ConstantVisitor(
    _evaluationEngine,
    _constructor.library as LibraryElementImpl,
    _externalErrorReporter,
    lexicalEnvironment: _parameterMap,
    lexicalTypeEnvironment: _typeParameterMap,
    substitution: Substitution.fromInterfaceType(definingType),
  );

  /// The node used for most error reporting.
  final AstNode _errorNode;

  final ConstructorElement _constructor;

  final List<DartType>? _typeArguments;

  final ConstructorInvocation _invocation;

  final Map<String, NamedExpression> _namedNodes;

  final Map<String, DartObjectImpl> _namedValues;

  final List<DartObjectImpl> _argumentValues;

  final Map<TypeParameterElement, DartType> _typeParameterMap = HashMap();

  final Map<String, DartObjectImpl> _parameterMap = HashMap();

  final Map<String, DartObjectImpl> _fieldMap = HashMap();

  /// Constructor for [_InstanceCreationEvaluator].
  ///
  /// This constructor is private, as the entry point for using a
  /// [_InstanceCreationEvaluator] is the static method,
  /// [_InstanceCreationEvaluator.evaluate].
  _InstanceCreationEvaluator._(
    this._evaluationEngine,
    this._declaredVariables,
    this._library,
    this._errorNode,
    this._constructor,
    this._typeArguments, {
    required Map<String, NamedExpression> namedNodes,
    required Map<String, DartObjectImpl> namedValues,
    required List<DartObjectImpl> argumentValues,
    required ConstructorInvocation invocation,
  })  : _namedNodes = namedNodes,
        _namedValues = namedValues,
        _argumentValues = argumentValues,
        _invocation = invocation;

  InterfaceType get definingType => _constructor.returnType;

  DartObjectImpl? get firstArgument => _argumentValues[0];

  TypeProvider get typeProvider => _library.typeProvider;

  TypeSystemImpl get typeSystem => _library.typeSystem;

  /// Evaluates this constructor call as a factory constructor call.
  Constant evaluateFactoryConstructorCall(
    List<Expression> arguments, {
    required bool isNullSafe,
  }) {
    final definingClass = _constructor.enclosingElement;
    var argumentCount = arguments.length;
    if (_constructor.name == "fromEnvironment") {
      if (!_checkFromEnvironmentArguments(arguments, definingType)) {
        return InvalidConstant(
            _errorNode, CompileTimeErrorCode.CONST_EVAL_THROWS_EXCEPTION);
      }
      String? variableName =
          argumentCount < 1 ? null : firstArgument?.toStringValue();
      if (definingClass == typeProvider.boolElement) {
        // Special case: https://github.com/dart-lang/sdk/issues/50045
        if (variableName == 'dart.library.js_util') {
          return DartObjectImpl(
            typeSystem,
            typeProvider.boolType,
            BoolState.UNKNOWN_VALUE,
          );
        }
        return FromEnvironmentEvaluator(typeSystem, _declaredVariables)
            .getBool2(variableName, _namedValues, _constructor);
      } else if (definingClass == typeProvider.intElement) {
        return FromEnvironmentEvaluator(typeSystem, _declaredVariables)
            .getInt2(variableName, _namedValues, _constructor);
      } else if (definingClass == typeProvider.stringElement) {
        return FromEnvironmentEvaluator(typeSystem, _declaredVariables)
            .getString2(variableName, _namedValues, _constructor);
      }
    } else if (_constructor.name == 'hasEnvironment' &&
        definingClass == typeProvider.boolElement) {
      final name = argumentCount < 1 ? null : firstArgument?.toStringValue();
      return FromEnvironmentEvaluator(typeSystem, _declaredVariables)
          .hasEnvironment(name);
    } else if (_constructor.name == "" &&
        definingClass == typeProvider.symbolElement &&
        argumentCount == 1) {
      if (!_checkSymbolArguments(arguments, isNullSafe: isNullSafe)) {
        return InvalidConstant(
            _errorNode, CompileTimeErrorCode.CONST_EVAL_THROWS_EXCEPTION);
      }
      return DartObjectImpl(
        typeSystem,
        definingType,
        SymbolState(firstArgument?.toStringValue()),
      );
    }
    // Either it's an external const factory constructor that we can't
    // emulate, or an error occurred (a cycle, or a const constructor trying to
    // delegate to a non-const constructor).
    //
    // In the former case, the best we can do is consider it an unknown value.
    // In the latter case, the error has already been reported, so considering
    // it an unknown value will suppress further errors.
    return DartObjectImpl.validWithUnknownValue(typeSystem, definingType);
  }

  Constant evaluateGenerativeConstructorCall(List<Expression> arguments) {
    InvalidConstant? error;

    // Start with final fields that are initialized at their declaration site.
    error = _checkFields();
    if (error != null) {
      return error;
    }

    _checkTypeParameters();

    error = _checkParameters(arguments);
    if (error != null) {
      return error;
    }

    final evaluationResult = _checkInitializers();
    final result = evaluationResult.result;
    if (result != null && evaluationResult.evaluationIsComplete) {
      return result;
    }

    error = _checkSuperConstructorCall(
        superName: evaluationResult.superName,
        superArguments: evaluationResult.superArguments);
    if (error != null) {
      return error;
    }

    return DartObjectImpl(
      typeSystem,
      definingType,
      GenericState(definingType, _fieldMap, invocation: _invocation),
    );
  }

  void _addImplicitArgumentsFromSuperFormals(List<Expression> superArguments) {
    var positionalIndex = 0;
    for (var parameter in _constructor.parameters) {
      if (parameter is SuperFormalParameterElement) {
        var value = SimpleIdentifierImpl(
          StringToken(TokenType.STRING, parameter.name, -1),
        )
          ..staticElement = parameter
          ..staticType = parameter.type;
        if (parameter.isPositional) {
          superArguments.insert(positionalIndex++, value);
        } else {
          superArguments.add(
            NamedExpressionImpl(
              name: LabelImpl(
                label: SimpleIdentifierImpl(
                  StringToken(TokenType.STRING, parameter.name, -1),
                )..staticElement = parameter,
                colon: StringToken(TokenType.COLON, ':', -1),
              ),
              expression: value,
            )..staticType = value.typeOrThrow,
          );
        }
      }
    }
  }

  /// Checks for any errors in the fields of [_constructor].
  ///
  /// Returns an [InvalidConstant] if one is found, or `null` otherwise.
  InvalidConstant? _checkFields() {
    final fields = _constructor.enclosingElement.fields;
    for (final field in fields) {
      if ((field.isFinal || field.isConst) &&
          !field.isStatic &&
          field is ConstFieldElementImpl) {
        final fieldValue = field.evaluationResult?.value;

        // It is possible that the evaluation result is null.
        // This happens for example when we have duplicate fields.
        // `class Test {final x = 1; final x = 2; const Test();}`
        if (fieldValue == null) {
          continue;
        }
        // Match the value and the type.
        var fieldType = FieldMember.from(field, _constructor.returnType).type;
        if (!typeSystem.runtimeTypeMatch(fieldValue, fieldType)) {
          return InvalidConstant(_errorNode,
              CompileTimeErrorCode.CONST_CONSTRUCTOR_FIELD_TYPE_MISMATCH,
              arguments: [fieldValue.type, field.name, fieldType]);
        }
        _fieldMap[field.name] = fieldValue;
      }
    }
    return null;
  }

  /// Check that the arguments to a call to `fromEnvironment()` are correct.
  ///
  /// The [arguments] are the AST nodes of the arguments. The [argumentValues]
  /// are the values of the unnamed arguments. The [namedArgumentValues] are the
  /// values of the named arguments. The [expectedDefaultValueType] is the
  /// allowed type of the "defaultValue" parameter (if present). Note:
  /// "defaultValue" is always allowed to be `null`. Return `true` if the
  /// arguments are correct, `false` otherwise.
  bool _checkFromEnvironmentArguments(
    List<Expression> arguments,
    InterfaceType expectedDefaultValueType,
  ) {
    var argumentCount = arguments.length;
    if (argumentCount < 1 || argumentCount > 2) {
      return false;
    }
    if (arguments[0] is NamedExpression) {
      return false;
    }
    if (firstArgument!.type != typeProvider.stringType) {
      return false;
    }
    if (argumentCount == 2) {
      var secondArgument = arguments[1];
      if (secondArgument is NamedExpression) {
        if (!(secondArgument.name.label.name == _defaultValueParam)) {
          return false;
        }
        var defaultValueType = _namedValues[_defaultValueParam]!.type;
        if (!(defaultValueType == expectedDefaultValueType ||
            defaultValueType == typeProvider.nullType)) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  /// Checks for any errors in the constant initializers of [_constructor].
  ///
  /// Returns an [_InitializersEvaluationResult] which contain a result from a
  /// redirecting constructor invocation, an [InvalidConstant], or an
  /// incomplete state for further evaluation.
  _InitializersEvaluationResult _checkInitializers() {
    var constructorBase = _constructor.declaration as ConstructorElementImpl;
    // If we encounter a superinitializer, store the name of the constructor,
    // and the arguments.
    String? superName;
    List<Expression>? superArguments;
    for (final initializer in constructorBase.constantInitializers) {
      if (initializer is ConstructorFieldInitializer) {
        final initializerExpression = initializer.expression;
        final evaluationResult =
            _initializerVisitor._getConstant(initializerExpression);
        switch (evaluationResult) {
          case DartObjectImpl():
            final fieldName = initializer.fieldName.name;
            if (_fieldMap.containsKey(fieldName)) {
              return _InitializersEvaluationResult(
                  InvalidConstant(initializerExpression,
                      CompileTimeErrorCode.CONST_EVAL_THROWS_EXCEPTION),
                  evaluationIsComplete: true);
            }
            _fieldMap[fieldName] = evaluationResult;
            final getter = definingType.getGetter(fieldName);
            if (getter != null) {
              final field = getter.variable;
              if (!typeSystem.runtimeTypeMatch(evaluationResult, field.type)) {
                return _InitializersEvaluationResult(
                    InvalidConstant(
                        initializerExpression,
                        CompileTimeErrorCode
                            .CONST_CONSTRUCTOR_FIELD_TYPE_MISMATCH,
                        arguments: [
                          evaluationResult.type,
                          fieldName,
                          field.type
                        ]),
                    evaluationIsComplete: true);
              }
            }
          case InvalidConstant():
            return _InitializersEvaluationResult(evaluationResult,
                evaluationIsComplete: true);
        }
      } else if (initializer is SuperConstructorInvocation) {
        final name = initializer.constructorName;
        if (name != null) {
          superName = name.name;
        }
        superArguments = initializer.argumentList.arguments.toList();
        _addImplicitArgumentsFromSuperFormals(superArguments);
      } else if (initializer is RedirectingConstructorInvocation) {
        // This is a redirecting constructor, so just evaluate the constructor
        // it redirects to.
        var constructor = initializer.staticElement;
        if (constructor != null && constructor.isConst) {
          // Instantiate the constructor with the in-scope type arguments.
          constructor = ConstructorMember.from(constructor, definingType);
          var result = _evaluationEngine.evaluateConstructorCall(
              _library,
              _errorNode,
              _typeArguments,
              initializer.argumentList.arguments,
              constructor,
              _initializerVisitor,
              _externalErrorReporter,
              invocation: _invocation);
          return _InitializersEvaluationResult(result,
              evaluationIsComplete: true);
        }
      } else if (initializer is AssertInitializer) {
        final condition = initializer.condition;
        final evaluationConstant = _initializerVisitor._getConstant(condition);
        switch (evaluationConstant) {
          case DartObjectImpl():
            if (!evaluationConstant.isBool ||
                evaluationConstant.toBoolValue() == false) {
              return _InitializersEvaluationResult(
                  InvalidConstant(initializer,
                      CompileTimeErrorCode.CONST_EVAL_ASSERTION_FAILURE),
                  evaluationIsComplete: true);
            }
          case InvalidConstant():
            return _InitializersEvaluationResult(evaluationConstant,
                evaluationIsComplete: true);
        }
      }
    }

    if (definingType.superclass != null && superArguments == null) {
      superArguments = [];
      _addImplicitArgumentsFromSuperFormals(superArguments);
    }

    return _InitializersEvaluationResult(null,
        evaluationIsComplete: false,
        superName: superName,
        superArguments: superArguments);
  }

  /// Checks for any errors in the parameters of [_constructor].
  ///
  /// Returns an [InvalidConstant] if one is found, or `null` otherwise.
  InvalidConstant? _checkParameters(List<Expression> arguments) {
    final parameters = _constructor.parameters;
    final parameterCount = parameters.length;

    for (var i = 0; i < parameterCount; i++) {
      final parameter = parameters[i];
      final baseParameter = parameter.declaration;
      DartObjectImpl? argumentValue;
      AstNode? errorTarget;
      if (baseParameter.isNamed) {
        argumentValue = _namedValues[baseParameter.name];
        errorTarget = _namedNodes[baseParameter.name];
      } else if (i < _argumentValues.length) {
        argumentValue = _argumentValues[i];
        errorTarget = arguments[i];
      }
      // No argument node that we can direct error messages to, because we
      // are handling an optional parameter that wasn't specified.  So just
      // direct error messages to the constructor call.
      errorTarget ??= _errorNode;
      if (argumentValue == null &&
          baseParameter is ParameterElementImpl &&
          baseParameter.isOptional) {
        // The parameter is an optional positional parameter for which no value
        // was provided, so use the default value.
        final evaluationResult = baseParameter.evaluationResult;
        if (evaluationResult == null) {
          // No default was provided, so the default value is null.
          argumentValue = ConstantEvaluationEngine._nullObject(_library);
        } else if (evaluationResult.value != null) {
          argumentValue = evaluationResult.value;
        }
      }
      if (argumentValue != null) {
        if (!argumentValue.isInvalid &&
            !typeSystem.runtimeTypeMatch(argumentValue, parameter.type)) {
          return InvalidConstant(errorTarget,
              CompileTimeErrorCode.CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH,
              arguments: [argumentValue.type, parameter.type]);
        }
        if (baseParameter.isInitializingFormal) {
          final field = (parameter as FieldFormalParameterElement).field;
          if (field != null) {
            final fieldType = field.type;
            if (fieldType != parameter.type) {
              // We've already checked that the argument can be assigned to the
              // parameter; we also need to check that it can be assigned to
              // the field.
              if (!argumentValue.isInvalid &&
                  !typeSystem.runtimeTypeMatch(argumentValue, fieldType)) {
                return InvalidConstant(errorTarget,
                    CompileTimeErrorCode.CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH,
                    arguments: [argumentValue.type, fieldType]);
              }
            }
            final fieldName = field.name;
            if (_fieldMap.containsKey(fieldName)) {
              return InvalidConstant(
                  _errorNode, CompileTimeErrorCode.CONST_EVAL_THROWS_EXCEPTION);
            }
            _fieldMap[fieldName] = argumentValue;
          }
        }
        _parameterMap[baseParameter.name] = argumentValue;
      }
    }
    return null;
  }

  /// Checks for errors in an explicit or implicit call to `super()`
  ///
  /// Returns an [InvalidConstant] if an error is found, or `null` otherwise.
  ///
  /// If a superinitializer was declared on the constructor declaration,
  /// [superName] and [superArguments] are the name of the super constructor
  /// referenced therein, and the arguments passed to the super constructor.
  /// Otherwise these parameters are `null`.
  InvalidConstant? _checkSuperConstructorCall({
    required String? superName,
    required List<Expression>? superArguments,
  }) {
    var superclass = definingType.superclass;
    if (superclass != null && !superclass.isDartCoreObject) {
      var superConstructor =
          superclass.lookUpConstructor(superName, _constructor.library);
      if (superConstructor == null) {
        return null;
      }

      final constructor = _constructor;
      if (constructor is ConstructorMember && constructor.isLegacy) {
        superConstructor =
            Member.legacy(superConstructor) as ConstructorElement;
      }
      if (superConstructor.isConst) {
        final evaluationResult = _evaluationEngine.evaluateConstructorCall(
          _library,
          _errorNode,
          superclass.typeArguments,
          superArguments ?? const [],
          superConstructor,
          _initializerVisitor,
          _externalErrorReporter,
        );
        switch (evaluationResult) {
          case DartObjectImpl():
            _fieldMap[GenericState.SUPERCLASS_FIELD] = evaluationResult;
          case InvalidConstant():
            evaluationResult.contextMessages.add(DiagnosticMessageImpl(
              filePath: _constructor.source.fullName,
              length: _constructor.nameLength,
              message:
                  "The evaluated constructor '${superConstructor.displayName}' "
                  "is called by '${_constructor.displayName}' and "
                  "'${_constructor.displayName}' is defined here.",
              offset: _constructor.nameOffset,
              url: null,
            ));
            return evaluationResult;
        }
      }
    }
    return null;
  }

  /// Checks that the arguments to a call to [Symbol.new] are correct.
  ///
  /// The [arguments] are the AST nodes of the arguments. The [argumentValues]
  /// are the values of the unnamed arguments. The [namedArgumentValues] are the
  /// values of the named arguments. Returns `true` if the arguments are
  /// correct, `false` otherwise.
  bool _checkSymbolArguments(List<Expression> arguments,
      {required bool isNullSafe}) {
    if (arguments.length != 1) {
      return false;
    }
    if (arguments[0] is NamedExpression) {
      return false;
    }
    if (firstArgument!.type != typeProvider.stringType) {
      return false;
    }
    var name = firstArgument?.toStringValue();
    if (name == null) {
      return false;
    }
    if (isNullSafe) {
      return true;
    }
    return _isValidPublicSymbol(name);
  }

  void _checkTypeParameters() {
    final typeParameters = _constructor.enclosingElement.typeParameters;
    final typeArguments = _typeArguments;
    if (typeParameters.isNotEmpty &&
        typeArguments != null &&
        typeParameters.length == typeArguments.length) {
      for (int i = 0; i < typeParameters.length; i++) {
        final typeParameter = typeParameters[i];
        final typeArgument = typeArguments[i];
        _typeParameterMap[typeParameter] = typeArgument;
      }
    }
  }

  /// Evaluates [node] as an instance creation expression using [constructor].
  static Constant evaluate(
    ConstantEvaluationEngine evaluationEngine,
    DeclaredVariables declaredVariables,
    ErrorReporter errorReporter,
    LibraryElementImpl library,
    AstNode node,
    ConstructorElement constructor,
    List<DartType>? typeArguments,
    List<Expression> arguments,
    ConstantVisitor constantVisitor, {
    required bool isNullSafe,
    ConstructorInvocation? invocation,
  }) {
    if (!constructor.isConst) {
      // TODO(kallentu): Retain token error information in InvalidConstant.
      if (node is InstanceCreationExpression && node.keyword != null) {
        errorReporter.reportErrorForToken(
            CompileTimeErrorCode.CONST_WITH_NON_CONST, node.keyword!);
      } else {
        errorReporter.reportErrorForNode(
            CompileTimeErrorCode.CONST_WITH_NON_CONST, node);
      }
      return InvalidConstant(node, CompileTimeErrorCode.CONST_WITH_NON_CONST);
    }

    if (!(constructor.declaration as ConstructorElementImpl).isCycleFree) {
      // It's not safe to evaluate this constructor, so bail out.
      // TODO(paulberry): ensure that a reasonable error message is produced
      // in this case, as well as other cases involving constant expression
      // cycles (e.g. "compile-time constant expression depends on itself").
      return DartObjectImpl.validWithUnknownValue(
        library.typeSystem,
        constructor.returnType,
      );
    }

    final argumentValues = <DartObjectImpl>[];
    final namedNodes = <String, NamedExpression>{};
    final namedValues = <String, DartObjectImpl>{};
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];

      // Use the corresponding parameter type as the default value if
      // an unresolved expression is evaluated. We do this to continue the
      // rest of the evaluation without producing unrelated errors.
      if (argument is NamedExpression) {
        final parameterType =
            argument.element?.type ?? InvalidTypeImpl.instance;
        final argumentConstant =
            constantVisitor._valueOf(argument.expression, parameterType);
        if (argumentConstant is! DartObjectImpl) {
          return argumentConstant;
        }

        final name = argument.name.label.name;
        namedNodes[name] = argument;
        namedValues[name] = argumentConstant;
      } else {
        final parameterType = i < constructor.parameters.length
            ? constructor.parameters[i].type
            : InvalidTypeImpl.instance;
        final argumentConstant =
            constantVisitor._valueOf(argument, parameterType);
        if (argumentConstant is! DartObjectImpl) {
          return argumentConstant;
        }

        argumentValues.add(argumentConstant);
      }
    }

    invocation ??= ConstructorInvocation(
      constructor,
      argumentValues,
      namedValues,
    );

    constructor = _followConstantRedirectionChain(constructor);
    final errorNode = evaluationEngine.configuration.errorNode(node);
    final evaluator = _InstanceCreationEvaluator._(
      evaluationEngine,
      declaredVariables,
      library,
      errorNode,
      constructor,
      typeArguments,
      namedNodes: namedNodes,
      namedValues: namedValues,
      argumentValues: argumentValues,
      invocation: invocation,
    );

    Constant constant;
    if (constructor.isFactory) {
      // We couldn't find a non-factory constructor.
      // See if it's because we reached an external const factory constructor
      // that we can emulate.
      constant = evaluator.evaluateFactoryConstructorCall(arguments,
          isNullSafe: isNullSafe);
    } else {
      constant = evaluator.evaluateGenerativeConstructorCall(arguments);
    }
    if (constant is InvalidConstant) {
      final formattedMessage =
          formatList(constant.errorCode.problemMessage, constant.arguments);
      final contextMessage = DiagnosticMessageImpl(
        filePath: library.source.fullName,
        length: constant.node.length,
        message: "The exception is '$formattedMessage' and occurs here.",
        offset: constant.node.offset,
        url: null,
      );
      errorReporter.reportErrorForNode(
        CompileTimeErrorCode.CONST_EVAL_THROWS_EXCEPTION,
        errorNode,
        [],
        [...constant.contextMessages, contextMessage],
      );
    }
    return constant;
  }

  /// Attempt to follow the chain of factory redirections until a constructor is
  /// reached which is not a const factory constructor. Return the constant
  /// constructor which terminates the chain of factory redirections, if the
  /// chain terminates. If there is a problem (e.g. a redirection can't be
  /// found, or a cycle is encountered), the chain will be followed as far as
  /// possible and then a const factory constructor will be returned.
  static ConstructorElement _followConstantRedirectionChain(
      ConstructorElement constructor) {
    var constructorsVisited = <ConstructorElement>{};
    while (true) {
      var redirectedConstructor =
          ConstantEvaluationEngine.getConstRedirectedConstructor(constructor);
      if (redirectedConstructor == null) {
        break;
      } else {
        var constructorBase = constructor.declaration;
        constructorsVisited.add(constructorBase);
        var redirectedConstructorBase = redirectedConstructor.declaration;
        if (constructorsVisited.contains(redirectedConstructorBase)) {
          // Cycle in redirecting factory constructors--this is not allowed
          // and is checked elsewhere--see
          // [ErrorVerifier.checkForRecursiveFactoryRedirect()]).
          break;
        }
      }
      constructor = redirectedConstructor;
    }
    return constructor;
  }

  /// Determine whether the given string is a valid name for a public symbol
  /// (i.e. whether it is allowed for a call to the Symbol constructor).
  static bool _isValidPublicSymbol(String name) =>
      name.isEmpty || name == "void" || _publicSymbolPattern.hasMatch(name);
}

extension on NamedType {
  bool get isTypeLiteralInConstantPattern {
    final parent = this.parent;
    return parent is TypeLiteral && parent.parent?.parent is ConstantPattern;
  }
}

extension RuntimeExtensions on TypeSystemImpl {
  /// Returns whether [obj] matches the [type] according to runtime
  /// type-checking rules.
  bool runtimeTypeMatch(
    DartObjectImpl obj,
    DartType type,
  ) {
    if (!isNonNullableByDefault) {
      type = toLegacyTypeIfOptOut(type);
    }
    var objType = obj.type;
    return isSubtypeOf(objType, type);
  }
}
