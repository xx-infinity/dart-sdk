// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/ast_factory.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/ast/utilities.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/extension_member_resolver.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';

/// A resolver for [FunctionReference] nodes.
///
/// This resolver is responsible for writing a given [FunctionReference] as a
/// [ConstructorReference] or as a [TypeLiteral], depending on how a function
/// reference's `function` resolves.
class FunctionReferenceResolver {
  /// The resolver driving this participant.
  final ResolverVisitor _resolver;

  /// Helper for extension method resolution.
  final ExtensionMemberResolver _extensionResolver;

  final bool _isNonNullableByDefault;

  /// The type representing the type 'type'.
  final InterfaceType _typeType;

  FunctionReferenceResolver(this._resolver, this._isNonNullableByDefault)
      : _extensionResolver = _resolver.extensionResolver,
        _typeType = _resolver.typeProvider.typeType;

  ErrorReporter get _errorReporter => _resolver.errorReporter;

  NullabilitySuffix get _nullabilitySuffixForTypeNames =>
      _isNonNullableByDefault ? NullabilitySuffix.none : NullabilitySuffix.star;

  void resolve(FunctionReferenceImpl node) {
    var function = node.function;
    node.typeArguments?.accept(_resolver);

    if (function is SimpleIdentifierImpl) {
      _resolveSimpleIdentifierFunction(node, function);
    } else if (function is PrefixedIdentifierImpl) {
      _resolvePrefixedIdentifierFunction(node, function);
    } else if (function is PropertyAccessImpl) {
      _resolvePropertyAccessFunction(node, function);
    } else if (function is ConstructorReferenceImpl) {
      var typeArguments = node.typeArguments;
      if (typeArguments != null) {
        // Something like `List.filled<int>`.
        function.accept(_resolver);
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_CONSTRUCTOR,
          typeArguments,
          [function.constructorName.type2.name, function.constructorName.name],
        );
        _resolve(node: node, rawType: function.staticType);
      }
    } else {
      // TODO(srawlins): Handle `function` being a [SuperExpression].

      function.accept(_resolver);
      var functionType = function.staticType;
      if (functionType == null) {
        _resolveDisallowedExpression(node, functionType);
      } else if (functionType is FunctionType) {
        _resolve(node: node, rawType: functionType);
      } else {
        var callMethodType =
            _resolver.typeSystem.getCallMethodType(functionType);
        if (callMethodType != null) {
          _resolve(node: node, rawType: callMethodType);
        } else {
          _resolveDisallowedExpression(node, functionType);
        }
      }
    }
  }

  /// Checks for a type instantiation of a `dynamic`-typed expression.
  ///
  /// Returns `true` if an error was reported, and resolution can stop.
  bool _checkDynamicTypeInstantiation(FunctionReferenceImpl node,
      PrefixedIdentifierImpl function, Element prefixElement) {
    DartType? prefixType;
    if (prefixElement is VariableElement) {
      prefixType = prefixElement.type;
    } else if (prefixElement is PropertyAccessorElement) {
      prefixType = prefixElement.returnType;
    }

    if (prefixType != null && prefixType.isDynamic) {
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.GENERIC_METHOD_TYPE_INSTANTIATION_ON_DYNAMIC,
        function,
        [],
      );
      node.staticType = DynamicTypeImpl.instance;
      return true;
    }
    return false;
  }

  List<DartType> _checkTypeArguments(
    TypeArgumentList typeArgumentList,
    String? name,
    List<TypeParameterElement> typeParameters,
    CompileTimeErrorCode errorCode,
  ) {
    if (typeArgumentList.arguments.length != typeParameters.length) {
      if (name == null &&
          errorCode ==
              CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION) {
        errorCode = CompileTimeErrorCode
            .WRONG_NUMBER_OF_TYPE_ARGUMENTS_ANONYMOUS_FUNCTION;
        _errorReporter.reportErrorForNode(
          errorCode,
          typeArgumentList,
          [typeParameters.length, typeArgumentList.arguments.length],
        );
      } else {
        assert(name != null);
        _errorReporter.reportErrorForNode(
          errorCode,
          typeArgumentList,
          [name, typeParameters.length, typeArgumentList.arguments.length],
        );
      }
      return List.filled(typeParameters.length, DynamicTypeImpl.instance);
    } else {
      return typeArgumentList.arguments
          .map((typeAnnotation) => typeAnnotation.typeOrThrow)
          .toList();
    }
  }

  void _reportInvalidAccessToStaticMember(
    SimpleIdentifier nameNode,
    ExecutableElement element, {
    required bool implicitReceiver,
  }) {
    if (_resolver.enclosingExtension != null) {
      _resolver.errorReporter.reportErrorForNode(
        CompileTimeErrorCode
            .UNQUALIFIED_REFERENCE_TO_STATIC_MEMBER_OF_EXTENDED_TYPE,
        nameNode,
        [element.enclosingElement.displayName],
      );
    } else if (implicitReceiver) {
      _resolver.errorReporter.reportErrorForNode(
        CompileTimeErrorCode.UNQUALIFIED_REFERENCE_TO_NON_LOCAL_STATIC_MEMBER,
        nameNode,
        [element.enclosingElement.displayName],
      );
    } else {
      _resolver.errorReporter.reportErrorForNode(
        CompileTimeErrorCode.INSTANCE_ACCESS_TO_STATIC_MEMBER,
        nameNode,
        [
          nameNode.name,
          element.kind.displayName,
          element.enclosingElement.displayName,
        ],
      );
    }
  }

  /// Resolves [node]'s static type, as an instantiated function type, and type
  /// argument types, using [rawType] as the uninstantiated function type.
  void _resolve({
    required FunctionReferenceImpl node,
    required DartType? rawType,
    String? name,
  }) {
    if (rawType == null) {
      node.staticType = DynamicTypeImpl.instance;
    }

    if (rawType is TypeParameterTypeImpl) {
      // If the type of the function is a type parameter, the tearoff is
      // disallowed, reported in [_resolveDisallowedExpression]. Use the type
      // parameter's bound here in an attempt to assign the intended types.
      rawType = rawType.element.bound;
    }

    if (rawType is FunctionType) {
      // A FunctionReference with type arguments and with a
      // ConstructorReference child is invalid. E.g. `List.filled<int>`.
      // [CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_CONSTRUCTOR] is
      // reported elsewhere; don't check type arguments here.
      if (node.function is ConstructorReference) {
        node.staticType = DynamicTypeImpl.instance;
      } else {
        var typeArguments = _checkTypeArguments(
          // `node.typeArguments`, coming from the parser, is never null.
          node.typeArguments!, name, rawType.typeFormals,
          CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION,
        );

        var invokeType = rawType.instantiate(typeArguments);
        node.typeArgumentTypes = typeArguments;
        node.staticType = invokeType;
      }
    } else {
      if (_resolver.isConstructorTearoffsEnabled) {
        // Only report constructor tearoff-related errors if the constructor
        // tearoff feature is enabled.
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
          node.function,
          [],
        );
      }
      node.staticType = DynamicTypeImpl.instance;
    }
  }

  void _resolveConstructorReference(FunctionReferenceImpl node) {
    // TODO(srawlins): Rewrite and resolve [node] as a constructor reference.
    node.function.accept(_resolver);
    node.staticType = DynamicTypeImpl.instance;
  }

  /// Resolves [node] as a [TypeLiteral] referencing an interface type directly
  /// (not through a type alias).
  void _resolveDirectTypeLiteral(
      FunctionReferenceImpl node, Identifier name, ClassElement element) {
    var typeArguments = _checkTypeArguments(
      // `node.typeArguments`, coming from the parser, is never null.
      node.typeArguments!, name.name, element.typeParameters,
      CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS,
    );
    var type = element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: _nullabilitySuffixForTypeNames,
    );
    _resolveTypeLiteral(node: node, instantiatedType: type, name: name);
  }

  /// Resolves [node] as a type instantiation on an illegal expression.
  ///
  /// This function attempts to give [node] a static type, to continue working
  /// with what the user may be intending.
  void _resolveDisallowedExpression(
      FunctionReferenceImpl node, DartType? rawType) {
    if (_resolver.isConstructorTearoffsEnabled) {
      // Only report constructor tearoff-related errors if the constructor
      // tearoff feature is enabled.
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
        node.function,
        [],
      );
    }
    _resolve(node: node, rawType: rawType);
  }

  void _resolveExtensionOverride(
    FunctionReferenceImpl node,
    PropertyAccessImpl function,
    ExtensionOverride override,
  ) {
    var propertyName = function.propertyName;
    var result =
        _extensionResolver.getOverrideMember(override, propertyName.name);
    var member = _resolver.toLegacyElement(result.getter);

    if (member == null) {
      node.staticType = DynamicTypeImpl.instance;
      return;
    }

    if (member.isStatic) {
      _resolver.errorReporter.reportErrorForNode(
        CompileTimeErrorCode.EXTENSION_OVERRIDE_ACCESS_TO_STATIC_MEMBER,
        function.propertyName,
      );
      // Continue to resolve type.
    }

    if (function.isCascaded) {
      _resolver.errorReporter.reportErrorForNode(
        CompileTimeErrorCode.EXTENSION_OVERRIDE_WITH_CASCADE,
        override.extensionName,
      );
      // Continue to resolve type.
    }

    if (member is PropertyAccessorElement) {
      function.accept(_resolver);
      _resolve(node: node, rawType: member.returnType);
      return;
    }

    _resolve(node: node, rawType: member.type, name: propertyName.name);
  }

  /// Resolve a possible function tearoff of a [FunctionElement] receiver.
  ///
  /// There are three possible valid cases: tearing off the `call` method of a
  /// function element, tearing off an extension element declared on [Function],
  /// and tearing off an extension element declared on a function type.
  Element? _resolveFunctionTypeFunction(
    Expression receiver,
    SimpleIdentifier methodName,
    FunctionType receiverType,
  ) {
    var methodElement = _resolver.typePropertyResolver
        .resolve(
          receiver: receiver,
          receiverType: receiverType,
          name: methodName.name,
          propertyErrorEntity: methodName,
          nameErrorEntity: methodName,
        )
        .getter;
    if (methodElement != null && methodElement.isStatic) {
      _reportInvalidAccessToStaticMember(methodName, methodElement,
          implicitReceiver: false);
    }
    return methodElement;
  }

  void _resolvePrefixedIdentifierFunction(
      FunctionReferenceImpl node, PrefixedIdentifierImpl function) {
    var prefixElement = function.prefix.scopeLookupResult!.getter;

    if (prefixElement == null) {
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.UNDEFINED_IDENTIFIER,
        function.prefix,
        [function.name],
      );
      function.staticType = DynamicTypeImpl.instance;
      node.staticType = DynamicTypeImpl.instance;
      return;
    }

    function.prefix.staticElement = prefixElement;
    function.prefix.staticType = prefixElement.referenceType;
    var functionName = function.identifier.name;

    if (prefixElement is PrefixElement) {
      var functionElement = prefixElement.scope.lookup(functionName).getter;
      if (functionElement == null) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.UNDEFINED_PREFIXED_NAME,
          function.identifier,
          [functionName, function.prefix.name],
        );
        function.staticType = DynamicTypeImpl.instance;
        node.staticType = DynamicTypeImpl.instance;
        return;
      } else {
        functionElement = _resolver.toLegacyElement(functionElement);
        _resolveReceiverPrefix(node, prefixElement, function, functionElement);
        return;
      }
    }

    if (_checkDynamicTypeInstantiation(node, function, prefixElement)) {
      return;
    }

    if (prefixElement is FunctionElement &&
        functionName == FunctionElement.CALL_METHOD_NAME) {
      _resolve(
        node: node,
        rawType: prefixElement.type,
        name: functionName,
      );
      return;
    }

    var functionType = _resolveTypeProperty(
      receiver: function.prefix,
      name: function.identifier,
      nameErrorEntity: function,
    );

    if (functionType != null) {
      if (functionType is FunctionType) {
        function.staticType = functionType;
        _resolve(
          node: node,
          rawType: functionType,
          name: functionName,
        );
        return;
      }
    }

    function.accept(_resolver);
    node.staticType = DynamicTypeImpl.instance;
  }

  void _resolvePropertyAccessFunction(
      FunctionReferenceImpl node, PropertyAccessImpl function) {
    function.accept(_resolver);
    var target = function.realTarget;

    DartType targetType;
    if (target is SuperExpressionImpl) {
      targetType = target.typeOrThrow;
    } else if (target is ThisExpressionImpl) {
      targetType = target.typeOrThrow;
    } else if (target is SimpleIdentifierImpl) {
      var targetElement = target.scopeLookupResult!.getter;
      if (targetElement is VariableElement) {
        targetType = targetElement.type;
      } else if (targetElement is PropertyAccessorElement) {
        targetType = targetElement.returnType;
      } else {
        // TODO(srawlins): Can we get here?
        node.staticType = DynamicTypeImpl.instance;
        return;
      }
    } else if (target is ExtensionOverrideImpl) {
      _resolveExtensionOverride(node, function, target);
      return;
    } else {
      var targetType = target.staticType;
      if (targetType != null && targetType.isDynamic) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.GENERIC_METHOD_TYPE_INSTANTIATION_ON_DYNAMIC,
          node,
          [],
        );
        node.staticType = DynamicTypeImpl.instance;
        return;
      }
      var functionType = _resolveTypeProperty(
        receiver: target,
        name: function.propertyName,
        nameErrorEntity: function,
      );

      if (functionType == null) {
        // The target is known, but the method is not; [UNDEFINED_GETTER] is
        // reported elsewhere.
        node.staticType = DynamicTypeImpl.instance;
        return;
      } else {
        if (functionType is FunctionType) {
          function.staticType = functionType;
          _resolve(
            node: node,
            rawType: functionType,
            name: function.propertyName.name,
          );
        }

        return;
      }
    }

    var propertyElement = _resolver.typePropertyResolver
        .resolve(
          receiver: function.realTarget,
          receiverType: targetType,
          name: function.propertyName.name,
          propertyErrorEntity: function.propertyName,
          nameErrorEntity: function,
        )
        .getter;

    if (propertyElement is TypeParameterElement) {
      _resolve(node: node, rawType: propertyElement!.type);
      return;
    }

    _resolve(
      node: node,
      rawType: function.staticType,
      name: propertyElement?.name,
    );
  }

  void _resolveReceiverPrefix(
    FunctionReferenceImpl node,
    PrefixElement prefixElement,
    PrefixedIdentifierImpl prefix,
    Element element,
  ) {
    if (element is MultiplyDefinedElement) {
      MultiplyDefinedElement multiply = element;
      element = multiply.conflictingElements[0];

      // TODO(srawlins): Add a resolution test for this case.
    }

    // Classes and type aliases are checked first so as to include a
    // PropertyAccess parent check, which does not need to be done for
    // functions.
    if (element is ClassElement || element is TypeAliasElement) {
      // A type-instantiated constructor tearoff like `prefix.C<int>.name` is
      // initially represented as a [PropertyAccess] with a
      // [FunctionReference] 'target'.
      if (node.parent is PropertyAccess) {
        _resolveConstructorReference(node);
        return;
      } else if (element is ClassElement) {
        node.function.accept(_resolver);
        _resolveDirectTypeLiteral(node, prefix, element);
        return;
      } else if (element is TypeAliasElement) {
        prefix.accept(_resolver);
        _resolveTypeAlias(node: node, element: element, typeAlias: prefix);
        return;
      }
    } else if (element is ExecutableElement) {
      node.function.accept(_resolver);
      _resolve(
        node: node,
        rawType: node.function.typeOrThrow as FunctionType,
        name: element.name,
      );
      return;
    } else if (element is ExtensionElement) {
      prefix.identifier.staticElement = element;
      prefix.identifier.staticType = DynamicTypeImpl.instance;
      prefix.staticType = DynamicTypeImpl.instance;
      _resolveDisallowedExpression(node, DynamicTypeImpl.instance);
      return;
    }

    assert(
      false,
      'Member of prefixed element, $prefixElement, is not a class, mixin, '
      'type alias, or executable element: $element (${element.runtimeType})',
    );
    node.staticType = DynamicTypeImpl.instance;
  }

  void _resolveSimpleIdentifierFunction(
      FunctionReferenceImpl node, SimpleIdentifierImpl function) {
    var element = function.scopeLookupResult!.getter;

    if (element == null) {
      DartType receiverType;
      var enclosingClass = _resolver.enclosingClass;
      if (enclosingClass != null) {
        receiverType = enclosingClass.thisType;
      } else {
        var enclosingExtension = _resolver.enclosingExtension;
        if (enclosingExtension != null) {
          receiverType = enclosingExtension.extendedType;
        } else {
          _errorReporter.reportErrorForNode(
            CompileTimeErrorCode.UNDEFINED_IDENTIFIER,
            function,
            [function.name],
          );
          function.staticType = DynamicTypeImpl.instance;
          node.staticType = DynamicTypeImpl.instance;
          return;
        }
      }

      var result = _resolver.typePropertyResolver.resolve(
        receiver: null,
        receiverType: receiverType,
        name: function.name,
        propertyErrorEntity: function,
        nameErrorEntity: function,
      );

      var method = result.getter;
      if (method != null) {
        if (method.isStatic) {
          _reportInvalidAccessToStaticMember(function, method,
              implicitReceiver: true);
          // Continue to assign types.
        }

        if (method is PropertyAccessorElement) {
          _resolve(node: node, rawType: method.returnType);
          return;
        }

        function.staticElement = method;
        function.staticType = method.type;
        _resolve(node: node, rawType: method.type, name: function.name);
        return;
      } else {
        _resolver.errorReporter.reportErrorForNode(
          CompileTimeErrorCode.UNDEFINED_METHOD,
          function,
          [function.name, receiverType],
        );
        function.staticType = DynamicTypeImpl.instance;
        node.staticType = DynamicTypeImpl.instance;
        return;
      }
    }

    // Classes and type aliases are checked first so as to include a
    // PropertyAccess parent check, which does not need to be done for
    // functions.
    if (element is ClassElement || element is TypeAliasElement) {
      // A type-instantiated constructor tearoff like `C<int>.name` or
      // `prefix.C<int>.name` is initially represented as a [PropertyAccess]
      // with a [FunctionReference] target.
      if (node.parent is PropertyAccess) {
        if (element is TypeAliasElement &&
            element.aliasedType is FunctionType) {
          function.staticElement = element;
          _resolveTypeAlias(node: node, element: element, typeAlias: function);
        } else {
          _resolveConstructorReference(node);
        }
        return;
      } else if (element is ClassElement) {
        function.staticElement = element;
        _resolveDirectTypeLiteral(node, function, element);
        return;
      } else if (element is TypeAliasElement) {
        function.staticElement = element;
        _resolveTypeAlias(node: node, element: element, typeAlias: function);
        return;
      }
    } else if (element is MethodElement) {
      function.staticElement = element;
      function.staticType = element.type;
      _resolve(node: node, rawType: element.type, name: element.name);
      return;
    } else if (element is FunctionElement) {
      function.staticElement = element;
      function.staticType = element.type;
      _resolve(node: node, rawType: element.type, name: element.name);
      return;
    } else if (element is PropertyAccessorElement) {
      function.staticElement = element;
      function.staticType = element.returnType;
      _resolve(node: node, rawType: element.returnType);
      return;
    } else if (element is ExecutableElement) {
      function.staticElement = element;
      function.staticType = element.type;
      _resolve(node: node, rawType: element.type);
      return;
    } else if (element is VariableElement) {
      function.staticElement = element;
      function.staticType = element.type;
      _resolve(node: node, rawType: element.type);
      return;
    } else if (element is ExtensionElement) {
      function.staticElement = element;
      function.staticType = DynamicTypeImpl.instance;
      _resolveDisallowedExpression(node, DynamicTypeImpl.instance);
      return;
    } else {
      _resolveDisallowedExpression(node, DynamicTypeImpl.instance);
      return;
    }
  }

  /// Returns the element that represents the property named [propertyName] on
  /// [classElement].
  ExecutableElement? _resolveStaticElement(
      ClassElement classElement, SimpleIdentifier propertyName) {
    String name = propertyName.name;
    ExecutableElement? element;
    if (propertyName.inSetterContext()) {
      element = classElement.getSetter(name);
    }
    element ??= classElement.getGetter(name);
    element ??= classElement.getMethod(name);
    if (element != null && element.isAccessibleIn(_resolver.definingLibrary)) {
      return element;
    }
    return null;
  }

  void _resolveTypeAlias({
    required FunctionReferenceImpl node,
    required TypeAliasElement element,
    required Identifier typeAlias,
  }) {
    var typeArguments = _checkTypeArguments(
      // `node.typeArguments`, coming from the parser, is never null.
      node.typeArguments!, element.name, element.typeParameters,
      CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS,
    );
    var type = element.instantiate(
        typeArguments: typeArguments,
        nullabilitySuffix: _nullabilitySuffixForTypeNames);
    _resolveTypeLiteral(node: node, instantiatedType: type, name: typeAlias);
  }

  void _resolveTypeLiteral({
    required FunctionReferenceImpl node,
    required DartType instantiatedType,
    required Identifier name,
  }) {
    // TODO(srawlins): set the static element of [typeName].
    // This involves a fair amount of resolution, as [name] may be a prefixed
    // identifier, etc. [TypeName]s should be resolved in [ResolutionVisitor],
    // and this could be done for nodes like this via [AstRewriter].
    var typeName = astFactory.namedType(
      name: name,
      typeArguments: node.typeArguments,
    );
    typeName.type = instantiatedType;
    typeName.name.staticType = instantiatedType;
    var typeLiteral = astFactory.typeLiteral(typeName: typeName);
    typeLiteral.staticType = _typeType;
    NodeReplacer.replace(node, typeLiteral);
  }

  /// Resolves [name] as a property on [receiver].
  ///
  /// Returns `null` if [receiver]'s type is `null`, a [TypeParameterType],
  /// or a type alias for a non-interface type.
  DartType? _resolveTypeProperty({
    required Expression receiver,
    required SimpleIdentifierImpl name,
    required SyntacticEntity nameErrorEntity,
  }) {
    if (receiver is Identifier) {
      var receiverElement = receiver.staticElement;
      if (receiverElement is ClassElement) {
        var element = _resolveStaticElement(receiverElement, name);
        name.staticElement = element;
        // TODO(srawlins): Should this use referenceType? E.g. if `element`
        // is a function-typed static getter.
        return element?.type;
      } else if (receiverElement is TypeAliasElement) {
        var aliasedType = receiverElement.aliasedType;
        if (aliasedType is InterfaceType) {
          var element = _resolveStaticElement(aliasedType.element, name);
          name.staticElement = element;
          // TODO(srawlins): Should this use referenceType? E.g. if `element`
          // is a function-typed static getter.
          return element?.type;
        } else {
          return null;
        }
      }
    }

    var receiverType = receiver.staticType;
    if (receiverType == null) {
      return null;
    } else if (receiverType is TypeParameterType) {
      return null;
    } else if (receiverType is FunctionType) {
      if (name.name == FunctionElement.CALL_METHOD_NAME) {
        return receiverType;
      }
      var element = _resolveFunctionTypeFunction(receiver, name, receiverType);
      name.staticElement = element;
      return element?.referenceType;
    }

    var element = _resolver.typePropertyResolver
        .resolve(
          receiver: receiver,
          receiverType: receiverType,
          name: name.name,
          propertyErrorEntity: name,
          nameErrorEntity: nameErrorEntity,
        )
        .getter;
    name.staticElement = element;
    if (element != null && element.isStatic) {
      _reportInvalidAccessToStaticMember(name, element,
          implicitReceiver: false);
    }
    return element?.referenceType;
  }
}

extension on Element {
  /// Returns the 'type' of `this`, when accessed as a "reference", not
  /// immediately followed by parentheses and arguments.
  ///
  /// For all elements that don't have a type (for example, [ExportElement]),
  /// `null` is returned. For [PropertyAccessorElement], the return value is
  /// returned. For all other elements, their `type` property is returned.
  DartType? get referenceType {
    if (this is ConstructorElement) {
      return (this as ConstructorElement).type;
    } else if (this is FunctionElement) {
      return (this as FunctionElement).type;
    } else if (this is PropertyAccessorElement) {
      return (this as PropertyAccessorElement).returnType;
    } else if (this is MethodElement) {
      return (this as MethodElement).type;
    } else if (this is VariableElement) {
      return (this as VariableElement).type;
    } else {
      return null;
    }
  }
}
