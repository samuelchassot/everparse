        .. _3d-lang:

The 3d Dependent Data Description language
==========================================

3d supports several fixed-width integer base types, (nested) structs,
constraints, enums, parameterized data types, tagged or otherwise
value-dependent unions, fixed-size arrays, and variable-size
arrays. In addition to data validation, 3d also supports *local
actions* to pass values read from the data structure, or pointers to
them, to the caller code.

Base types
----------

The primitive types in 3d include unsigned integers of the following
flavors:

* UINT8: 8-bit unsigned little-endian integer
* UINT16: 16-bit unsigned little-endian integer
* UINT32: 32-bit unsigned little-endian integer
* UINT64: 64-bit unsigned little-endian integer

We also provide big-endian unsigned integers:

* UINT16BE: 16-bit unsigned big-endian integer
* UINT32BE: 32-bit unsigned big-endian integer
* UINT64BE: 64-bit unsigned big-endian integer

Big-endian integers are often useful in describing network message
formats. 3d ensures suitable endianness conversions are applied when
comparing or equating integers represented in different endianness. We
show an example of this :ref:`below <sec-constraints>`.

Structs
-------

We would like to extract a validator for a simple point type, with X
and Y coordinates. So we create a file, ``HelloWorld.3d``, with the
following 3d data format description:

.. literalinclude:: HelloWorld.3d
    :language: c

This data format is very similar to a C type description, where
``UINT16`` denotes the type of unsigned 16-bit integers, represented
as little-endian; with the addition of the ``entrypoint`` keyword,
which tells 3d to expose the validator for the type to the final user.

Once we run ``3d`` with this file, we obtain several files:

* ``HelloWorld.c`` and ``HelloWorld.h``, which contain the actual verified
  validators;

* ``HelloWorldWrapper.c`` and ``HelloWorldWrapper.h``, which contain
  entrypoint function definitions for data validators that the user
  should ultimately use in their client code. More precisely, here is
  the contents of ``HelloWorldWrapper.h``:

.. literalinclude:: HelloWorldWrapper.h
    :language: c
    :start-after: SNIPPET_START: Point
    :end-before: SNIPPET_END: Point

The ``HelloWorldCheckPoint`` function is the actual validator for the
``point`` type. It takes an array of bytes, ``base``, and its length
``len``, and it returns 1 if ``base`` starts with valid ``point`` data
that fits in ``len`` bytes or less, and 0 otherwise.

More generally, for a given ``Module.3d``, a type definition ``typ``
marked with ``entrypoint`` tells 3d to expose its validator in
``ModuleWrapper.h`` which will bear the name ``ModuleCheckTyp``.

Structs can be nested, such as in the following instance:

.. literalinclude:: Triangle.3d
    :language: c

Then, since in this file the definition of ``point`` is not prefixed
with ``entrypoint``, only ``triangle`` will have its validator exposed
in ``TriangleWrapper.h``.

There can be multiple definitions marked ``entrypoint`` in a given
``.3d`` file.

.. warning::

  3d does not enforce any alignment constraints, and does not
  introduce any implicit alignment padding. So, for instance, in the
  following data format description:

  .. literalinclude:: ColoredPoint.3d
      :language: c

  * in ``coloredPoint1``, 3d will not introduce any padding between
    the ``color`` field and the ``pt`` field;

  * in ``coloredPoint2``, 3d will not introduce any padding after the
    ``color`` field.

.. _sec-constraints:

Constraints
-----------

Validators for structs alone are only layout-related. Beyond that, 3d
provides a way to actually check for constraints on their field
values:

.. literalinclude:: Smoker.3d
    :language: c

In this example, the validator for ``smoker`` will check that the
value of the ``age`` field is at least 21.

The constraint language includes integer arithmetic (``+``, ``-``,
``*``, ``/``, ``==``, ``!=``, ``<=``, ``<``, ``>=``, ``>``) and
Boolean propositional logic (``&&``, ``||``, ``!``)

Constraints on a field can also depend on the values of the previous
fields of the struct. For instance, here is a type definition for a
pair ordered by increasing values:

.. literalinclude:: OrderedPair.3d
    :language: c

.. warning::

   Arithmetics on constraints are evaluated in machine integers, not
   mathematical integers. Thus, the following naive definition:

   .. literalinclude:: BoundedSumConst.3d
       :language: c
       :start-after: SNIPPET_START: boundedSumNaive
       :end-before: SNIPPET_END: boundedSumNaive

   will fail at F* verification because the expression ``left + right``
   must be proven to not overflow *before* evaluating the condition. The
   correct way of stating the condition is as follows:

   .. literalinclude:: BoundedSumConst.3d
       :language: c
       :start-after: SNIPPET_START: boundedSumCorrect
       :end-before: SNIPPET_END: boundedSumCorrect

   This verifies because F* evaluates the right-hand-side
   condition of a ``&&`` in a context where the left-hand-side
   condition is assumed to be true (thus ``42 - left`` will not underflow.)

Bitfields
---------

Like in C, the fields of a struct type in 3d can include bitfields,
i.e., unsigned integer types of user-specified width represented
packed within unsigned integer fields of the canonical sizes
UINT16, UINT32 and UINT64.

Consider the following example:

.. literalinclude:: BF.3d
    :language: c
    :start-after: SNIPPET_START: BF
    :end-before: SNIPPET_END: BF

This defines a struct ``BF`` occupying 32 bits of memory, where the
first 6 bits are for the field ``x``; the next 10 bits are for the
field ``y``; and the following 16 bits are for the field ``z``.

The fields ``x``, ``y``, and ``z`` can all be used in specifications
and are implicitly promoted to the underlying integer type, ``UINT32``
in this case, although the 3d verifier is aware of suitable bounds on
the types, e.g., that ``0 <= x < 64``.

3d implements C's rules for packing bit fields. For instance,

.. literalinclude:: BF.3d
    :language: c
    :start-after: SNIPPET_START: BF2
    :end-before: SNIPPET_END: BF2

In ``BF2``, although ``x``, ``y`` and ``z`` cumulatively consume only
26 bits, the layout of ``BF2`` is actually as shown below, consuming
40 bits, since a given field must be represented within the bounds of
a single underlying type---we have 10 unused bits after ``x`` and 4
unused bits after ``y``.

.. code-block:: c

    0                   1                   2                   3                   4
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
   |     x     |       Unused      |           y           |Unused |        z      |
   |           |                   |                       |       |               |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
                

Constants and Enumerations
--------------------------

3d provides a way to define numerical constants:

.. literalinclude:: ConstColor.3d
    :language: c

Alternatively, 3d provides a way to define enumerated types:

.. literalinclude:: Color.3d
    :language: c

The validator for ``coloredPoint`` will check that the value of
the field ``col`` is either 1, 2 (for ``green``), or 42.

Contrary to structs, enum types cannot be marked ``entrypoint``.

The first enum label must be associated with a value.

The support type (here ``UINT32``) must be the same type as the type
of the values associated to each label.

Due to a limitation in the way 3d currently checks for the absence of
double-fetches, values with enum type cannot be used in
constraints. For example, the following code is currently rejected.

.. code-block:: c
                
  UINT32 enum color {
    red = 1,
    green,
    blue = 42
  };

  typedef struct _enum_constraint {
    color col;
    UINT32 x
    {
       x == 0 || color == green
    };
  } _enum_constraint ;

With the following error message:

.. code-block:: c

   (Error) The type of this field does not have a reader, either because its values are too large or because reading it may incur a double fetch; subsequent fields cannot depend on it


One must instead write:

.. literalinclude:: EnumConstraint.3d

We expect to lift this limitation soon.


Parameterized data types
------------------------

3d also offers the possibility to parameterize a data type description
with arguments that can then be reused in constraints. For instance,
the following ``BoundedSum.3d`` data description defines a pair of two
integers whose sum is bounded by a bound provided by the user as
argument:

.. literalinclude:: BoundedSum.3d
    :language: c
    :start-after: SNIPPET_START: boundedSum
    :end-before: SNIPPET_END: boundedSum

Then, these arguments will show up as arguments of the
corresponding validator in the ``BoundedSumWrapper.h`` header produced
by 3d:

.. literalinclude:: BoundedSumWrapper.h
    :language: c
    :start-after: SNIPPET_START: BoundedSum
    :end-before: SNIPPET_END: BoundedSum

Parameterized data types can also be instantiated within the ``.3d``
file itself, including by the value of the field of a struct:

.. literalinclude:: BoundedSum.3d
    :language: c
    :start-after: SNIPPET_START: mySum
    :end-before: SNIPPET_END: mySum

A parameterized data type can also check whether a condition on its
arguments holds before even trying to check its contents:

.. literalinclude:: BoundedSumWhere.3d
    :language: c

In this case, the validator for ``boundedSum`` would check
that ``bound <= 1729``, before validating its fields.
   

Tagged unions
-------------

3d supports *tagged unions*: a data type can store a value named *tag*
and a *payload* whose type depends on the tag value. The tag does not
need to be stored with the payload (e.g. it could be a parameter to the
type).

For instance, the following description defines the type of an integer
prefixed by its size in bits.

.. literalinclude:: TaggedUnion.3d
    :language: c

.. warning::

  3d does not enforce that all cases of a union be of the same size,
  and 3d does not introduce any implicit padding to enforce it. Nor
  does 3d introduce any alignment padding. This is in the spirit of
  keeping 3d specifications explicit: if you want padding, you need to
  add it explicitly.

A ``casetype`` type actually defines an untagged union type dependent
on an argument value, which can be reused, e.g. for several types that
put different constraints on the value of the tag.

A ``casetype`` type can also be marked ``entrypoint``.


Arrays
------

A field in a struct or a casetype can be an array.

Arrays in 3d differ from arrays in C in a few important ways:

* Rather than counting elements, the size of an array in 3d is always
  given in bytes.

* Array sizes need not be a constant expression: any integer
  expression is permissible for an array, so long as it fits in
  ``UINT32``. This allows expressing variable-sized arrays.
  
3d supports several kinds of arrays.

Byte-sized arrays
.................

* ``T f[:byte-size n]``
  
The notation ``T f[:byte-size n]`` describes a field named ``f`` holding an
array of elements of type ``T`` whose cumulative size in bytes is ``n``.

When ``sizeof(T) = 1``, 3d supports the notation ``T f[n]``, i.e., for
byte arrays, since the byte size and element count coincide, you need
not qualify the size of the array with a ``:byte-size`` qualifier.

Singleton arrays of variable size
.................................

* ``T f[:byte-size-single-element-array n]``
  
In some cases, it is required to specify that a field contains a
single variable-sized element whose size in bytes is equal to a given
expression. The notation above introduces a field ``f`` that contains
a single element of type ``T`` occupying exactly ``n`` bytes.

A variation is:

* ``T f[:byte-size-single-element-array-at-most n]``

similar to the previous form, but where ``n`` is an upper bound on the
size in bytes.

We expect to add several other kinds of variable-length array-like
types in the uture.

Actions
-------

In addition to semantic constraints on types, 3d allows augmenting the
the fields of a struct or union with imperative actions, which allows
running certain user-chosen commands at specified points during
validation.

Let's start with a simple example. Suppose you want to validate that a
byte array contains a pair of integers, and then read them into a
couple of mutable locations of your choosing. Here's how:

.. literalinclude:: ReadPair.3d
    :language: c

The struct ``Pair`` takes two out-parameters, ``x`` and ``y``. Out
parameters are signified by the ``mutable`` keyword and have pointer
types---in this case ``UINT32*``. Each field in the struct is
augmented with an ``on-success`` action, where the action's body is a
runs a small program snippet, which writes the ``first`` field into
``x``; the ``second`` field into ``y``; and returns ``true`` in both
cases. Actions can also return ``false``, to signal that validation
should halt and signal failure.

Now, in greater detail:

Action basics
.............

An action is a program composed from a few elements:

* Atomic actions: Basic commands to read and write variables
  
* Variable bindings and sequential composition
  
* Conditionals

An action is evaluated with respect to a handler (e.g.,
``on-success``) associated with a given field. We refer to this field
as the "base field" of the action.

An action is invoked by EverParse immediately after validating the
base field of the action. The action of the ``on-success`` handler is
invoked in case the field is valid (if preseent), otherwise the
``on-error`` handler is invoked (if present).

The on-success handler can influence whether or not validation of the
other fields continues by returning a boolean---in case an on-success
action returns false, the validation of the type halts with an error.

The on-error handler also returns a boolean: in case it returns false,
the error code associated with the validator mentions that an
on-error handler failed; if it returns true, the error code is the
error code associated with the failed validation of the base field. In
both cases, validation halts with an error.


Atomic actions
^^^^^^^^^^^^^^

* Expression ``e`` consist of variables and constants.

* ``*i = e``: Assigns the value of the expressions ``e`` to the memory referenced by the pointer ``i``.
  
* ``*i``: Dereferences the pointer ``i``

* ``field_pos``: Returns the offset of base field of the action from
  the base of the validation buffer as a ``UINT32`` value.

* ``field_ptr``: Returns a pointer to base field of the action as a
  ``PUINT8``, i.e., an abstract pointer to a ``UINT8``.

* ``return e`` Returns a boolean value ``e``

* ``abort``: Causes the current validation process to fail.
  
We plan to support additional user-defined actions as callbacks to
external C functions.
  

Composing atomic actions sequentially and conditionally
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Composite actions can be built in a few ways:

* Atomic actions: For any atomic action ``a``, ``a;`` (with a trailing
  semicolon) is a composite action ``p``.

* Sequential composition: ```a; p`` Given an atomic action ``a``, and
  a compositite action ``p``, the form ``a;p`` runs ``a`` then ``p``.

* Variable binding: ``var x = a; p`` Given an atomic action ``a``,
  and a compositite action ``p``, the form ``var x = a; p`` runs ``a``,
  stores its result in the new variable ``x`` (local to the
  action), and then runs ``p`` (where ``p`` may mention `x`

* Conditionals: ``if (e) { p }`` is a conditional action that runs the
  composite actions ``p`` only if the condition ``e`` is
  true. Additionally, ``if (e) { p0 } else { p1 }`` is also legal,
  with the expected semantics, i.e., ``p1` is run in case ``e`` is
  false.

Another example
^^^^^^^^^^^^^^^

Consider the following definition:

.. literalinclude:: GetFieldPtr.3d
    :language: c
    :start-after: SNIPPET_START: GetFieldPtr.T
    :end-before: SNIPPET_END: GetFieldPtr.T

Here, we define a type ``T`` with an out-parameter ``PUINT8* out``,
i.e., pointer to a pointer to a ``UINT8``.

Associated with field ``f2`` we have an on-success handler, where we
read a pointer to the field ``f2`` into the local variable ``x``;
then, we write ``x`` into ``*out``; and finally return ``true``.

.. note:: The return type of ``field_ptr`` is ``PUINT8``. In
   EverParse, a ``PUINT8`` is a pointer into the input buffer, unlike
   a ``UINT8*`` which may point to any other memory. This distinction
   between pointers into the input buffer and other pointers allows
   EverParse to prove that validators never read the contents of the
   input buffer more than once, i.e., there are no double fetches from
   the input buffer. As such, the ``out`` parameter should have type
   ``PUINT8*`` rather than ``UINT8*``.

Restrictions
............

* Actions can only be associated with fields.

* Actions cannot be associated with the elements of an array, unless
  the array elements themselves are defined types, in which case they
  can be associated with the fields of that type, if any.

* Actions cannot be associated with bit fields.

Checking 3d types for correspondence with existing C types
----------------------------------------------------------

A typical scenario is that you have an existing C program with some
collection of types defined in a file ``Types.h``.  You've written a
``Types.3d`` file to defined validators for byte buffers containing
those types, typically *refining* the C types with additional semantic
constraints and also with actions. Now, you may want to make sure that
types you defined in ``Types.3d`` correspond to the types in
``Types.h``, e.g., to ensure that you didn't forget to include a field
in a struct, or that you've made explicit in your ``Types.3d`` the
alignment padding between struct fields that a C compiler is sometimes
requires to insert.

To assist with this, 3d provides the following feature:

.. literalinclude:: GetFieldPtr.3d
    :language: c

Following the type definitions, the ``refining`` section states that
the type ``S`` defined in the C header file ``GetFieldPtrBase.h`` is
refined by the type ``T`` defined here. As a result of this
declaration, 3d emits a static assertion in the C code of the form

.. code-block:: c

  #include "GetFieldPtrBase.h"
  C_ASSERT(sizeof(S) == 30);
   
checking that the ``sizeof(S)`` as computed by the C compiler matches
3d's computation of the ``sizeof(T)``.

In generality, the refining declaration takes the following form:

.. code-block:: c
                
  refining "I1.h", ..., "In.h" {
      S1 as T1, ...
      Sm as Tm
  }


where each ``Si`` is a type defined in one of the C header files
"I1.h", ..., "In.h", and the ``Ti`` are types defined in the current
3d file. In case the types have the same names, one can simply write
``T`` instead of ``T as T``.

  
Comments
--------

The user can insert comments in their ``.3d`` file, some of which will
be inserted into the ``.c`` file:

There are three kinds of comments:

* Block comments are delimited by ``/*`` and ``*/`` and do not
  nest. These are never propagated to the C code.
  
* Line comments begin with ``//`` and are propagated to C
  heuristically close to the translated source construct.
  
* Each top-level declaration can be preceded by a type declaration
  comment delimited by ``/*++`` and ``--*/``: These are propagated to
  the C code preceding the C procedure corresponding to the validator
  of the source type.


Adding copyright notices to produced .c/.h files
------------------------------------------------

If, along with some ``MyFile.3d``, in the same directory, you provide
a file ``MyFile.3d.copyright.txt`` that contains syntactically correct
C comments (with ``//`` or ``/* ... */``), then EverParse will prepend
``MyFile.c``, ``MyFileWrapper.c`` and their corresponding ``.h`` with
these comments. You do not need to mention this file on the command
line.

These comments can contain the following special symbols:

* ``EVERPARSEVERSION``, which EverParse will automatically replace
  with its version number;

* ``FILENAME``, which EverParse will automatically replace with the
  name of the ``.c`` / ``.h`` file being generated.

* ``EVERPARSEHASHES``, which EverParse will automatically replace with
  a hash of the contents of the corresponding .3d file for the purpose
  of ``--check_hashes inplace`` or ``--check_inplace_hash`` (see `Hash
  checking <3d.html#alternate-mode-hash-checking>`_).

  
Modular structure and files
---------------------------

A 3d specification is described in a collection of modules, each
stored in a file with a ``.3d`` extension. The name of a module is
derived from its filename, i.e., the file ``A.3d`` defines a module
named ``A``. A module can ``Derived`` (in Derived.3d) can refer to
another module ``Base`` (in Base.3d) by its name, allowing definitions
in ``Derived`` to reuse the definitions that are exported in ``Base``.

For example, in module ``Base`` we could define the following types:

.. literalinclude:: Base.3d
    :language: c

Note, the ``export`` qualifier indicate that these definitions may be
referenced from another module. Types that are not exproted (like
``Mine``) are not visible from another module.

In ``Derived`` we can use the type from ``Base`` by referring to it
using a fully qualified name of the form ``<MODULE NAME>.<IDENTIFIER>``.

.. literalinclude:: Derived.3d
   :language: c
   :start-after: SNIPPET_START: Triple
   :end-before: SNIPPET_END: Triple


3d also allows defining module abbreviations. For example, using
``module B = Base`` we introduce a shorter name for the module
``Base`` for use within the current module.

.. literalinclude:: Derived.3d
   :language: c
   :start-after: SNIPPET_START: Quad
   :end-before: SNIPPET_END: Quad

A commented example is available `in the EverParse repository
<https://github.com/project-everest/everparse/blob/master/src/3d/tests/modules/>`_.

Error handling
--------------

When a validator fails, EverParse supports invoking a user-provided
callback with contextual information about the failure.

An error handling callback is a C procedure with the following signature:

.. code-block:: c

  typedef void (*ErrorHandler)(
    const char *TypeName,
    const char *FieldName,
    const char *ErrorReason,
    uint64_t ErrorCode,
    uint8_t *Context,
    uint32_t Length,
    uint8_t *Base,
    uint64_t StartPosition,
    uint64_t EndPosition
  );
    
Every EverParse validator is parameterized by:

* A function pointer, of type ``ErrorHandler``
* A context parameter, ``uint8_t* Context``

At the top-level, when calling into EverParse from an application, one
can instantiate both the ``ErrorHandler`` with a function of one's
choosing and the ``Context`` argument with a pointer to some
application-specific context.

The ``ErrorHandler`` expects

  * The ``Base`` and ``Context`` pointers to refer to live and
    disjoint pieces of memory.

  * For ``Length`` to be the length in bytes of valid memory pointed
    to by ``Base`` and for ``StartPosition <= EndPosition <= Length``.

The ``ErrorHandler`` can

  * Read from all the pointers

  * May only modify the memory reference by ``Context``.

When validating a field ``f`` in a type ``T``, in case the validator
fails, EverParse calls the user-provided ``ErrorHandler``, passing in
the following arguments:

  * The ``TypeName`` argument is the name of the type ``T``

  * The ``FieldName`` argument is name of the field ``f``

  * The ``ErrorReason`` and ``ErrorCode`` arguments are related and can be one of the following pairs:
    
    - "generic error", ``EVERPARSE_ERROR_GENERIC`` (1uL)
    - "not enough data", ``EVERPARSE_ERROR_NOT_ENOUGH_DATA`` (2uL)
    - "impossible", ``EVERPARSE_ERROR_IMPOSSIBLE`` (3uL)
    - "list size not multiple of element size", ``EVERPARSE_ERROR_LIST_SIZE_NOT_MULTIPLE`` (4uL)
    - "action failed", ``EVERPARSE_ERROR_ACTION_FAILED`` (5uL)
    - "constraint failed", ``EVERPARSE_ERROR_CONSTRAINT_FAILED`` (6uL)
    - "unexpected padding", ``EVERPARSE_ERROR_UNEXPECTED_PADDING`` (7uL)
    - "unspecified", with the ``ErrorCode > 7uL``

  * The ``Context`` argument is the user-provided ``Context`` pointer
    
  * The ``Length`` argument is the length in bytes of the input buffer

  * The ``Base`` argument is a pointer to the base of the input buffer

  * The ``StartPosition`` argument is the offset from ``Base`` of the
    start of the field ``f``
  
  * The ``EndPosition`` argument is the offset from ``Base`` of the
    end of the field ``f`` at which the validation failure occurred.
                
Following a validation failure at a given field, EverParse will invoke
the ``ErrorHandler`` at each enclosing type as well. This allows a
caller to reconstruct a stack trace of a failing validation.

EverParse generates a default error handler that records just the
deepest validation failure that occurred.

Fully worked examples: TCP Segment Headers
-------------------------------------------

The classic `IETF RFC 793 <https://tools.ietf.org/html/rfc793>`_ from
1981 introduces the TCP protocol, including the format of the header
of TCP segments. The format has been extended slightly since then, to
accommodate new options and flags---this `Wikipedia page
<https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_segment_structure>`_
provides a good summary. 

Reproduced below is an ASCII depiction of the format of TCP
headers. In this section, we show how to specify this format in
3d. The full specification can be found `here <https://github.com/project-everest/everparse/tree/master/src/3d/tests/tcpip/TCP.3d>`_.


.. code-block:: c

    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |          Source Port          |       Destination Port        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                        Sequence Number                        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                    Acknowledgment Number                      |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |  Data |     |N|C|E|U|A|P|R|S|F|                               |
   | Offset| Rese|S|W|C|R|C|S|S|Y|I|            Window             |
   |       | rved| |R|E|G|K|H|T|N|N|                               |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |           Checksum            |         Urgent Pointer        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                    Options                    |    Padding    |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                             data                              |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+


Each ``-`` in the diagram represents a single bit, with fioelds
separated by vertical bars ``|``.

The main subtle element of the specification is the handling of the
``DataOffset`` field. It is a 4-bit value representing an offset from
the beginning of the segment, in 32-bit increments, of the start of
the ``data`` field. The ``Options`` and ``Padding`` fields are
optional, so the ``DataOffset`` field is used to encode the size of
the ``Options`` field. As such, ``DataOffset`` is always at least
``5``.

The ``Options`` field itself is an array of tagged unions,
representing various kinds of options. Padding and the end of the
options array ensures that the ``data`` fields is always begins at a
multiple of 32-bits from the start of the segment.

Additionally, semantic constraints restrict the values of the fields
depending on the values of some other fields. For example, the
Acknowledgement number can only be non-zero when the ``ACK`` bit is
set.

To specify the type of a TCP header, we begin by defining some basic
types.

.. code-block:: c

  typedef UINT16 PORT;
  typedef UINT32 SEQ_NUMBER;
  typedef UINT32 ACK_NUMBER;
  typedef UINT16 WINDOW;
  typedef UINT16 CHECK_SUM;
  typedef UINT16 URGENT_PTR;

The source and destination port each occupy 16 bits and are
represented by a ``UINT16``; the sequence and acknowledgment number
fields are ``UINT32`` etc.

Next, we define the various kind of options that are allowed. Every
option begins with an option kind tag, an 8-bit value. Depending on
the option kind, a variable number of bits of an option value can
follow. The permitted option kinds are:

.. code-block:: c

  #define OPTION_KIND_END_OF_OPTION_LIST 0x00
  #define OPTION_KIND_NO_OPERATION 0x01
  #define OPTION_KIND_MAX_SEG_SIZE 0x02
  #define OPTION_KIND_WINDOW_SCALE 0x03
  #define OPTION_KIND_SACK_PERMITTED 0x04
  #define OPTION_KIND_SACK 0x05
  #define OPTION_KIND_TIMESTAMP 0x08

An ``OPTION`` is parameterized by a boolean, ``MaxSegSizeAllowed``,
which constraints when the ``OPTION_KIND_MAX_SEG_SIZE`` is allowed to
be present---it turns out, the ``SYN`` bit in the header must be set
for this option to be allowed. The general shape of an ``OPTION`` is
as below.

.. code-block:: c

  typedef struct _OPTION(Bool MaxSegSizeAllowed)
  {
      UINT8 OptionKind;
      OPTION_PAYLOAD(OptionKind, MaxSegSizeAllowed) OptionPayload;
  } OPTION;

We have an ``OptionKind`` field followed by an ``OptionPayload`` that
depends on the ``OptionKind`` and the ``MaxSegSizeAllowed`` flag.

Next, to define the ``OPTION_PAYLOAD`` type, we use a ``casetype``, as
shown below.

.. code-block:: c

  casetype _OPTION_PAYLOAD(UINT8 OptionKind, Bool MaxSegSizeAllowed)
  {
    switch(OptionKind)
    {
     case OPTION_KIND_END_OF_OPTION_LIST:
       unit EndOfList;
       
     case OPTION_KIND_NO_OPERATION:
       unit Noop;

     case OPTION_KIND_MAX_SEG_SIZE:
       MAX_SEG_SIZE_PAYLOAD(MaxSegSizeAllowed) MaxSegSizePayload;

     case OPTION_KIND_WINDOW_SCALE:
       WINDOW_SCALE_PAYLOAD WindowScalePayload;

     case OPTION_KIND_SACK_PERMITTED:
       UINT8 SackPermittedPayload;

     case OPTION_KIND_SACK:
       SELECTIVE_ACK_PAYLOAD SelectiveAckPayload;

     case OPTION_KIND_TIMESTAMP:
       TIMESTAMP_PAYLOAD TimestampPayload;
    } 
  } OPTION_PAYLOAD;

In the first two cases of ``OptionKind``, no payload is expected. The
``unit`` type in 3d is an empty type---it consumes no space in the
message format.

For ``OPTION_KIND_MAX_SEG_SIZE``, we have the following payload---the
use of the ``where` constraint ensures that this case is present only
when `MaxSegSizeAllowed == true``. The payload is a length field (4
bytes) and a 2-byte ``MaxSegSize`` value.

.. code-block:: c

  typedef struct _MAX_SEG_SIZE_PAYLOAD(Bool MaxSegSizeAllowed)
  where MaxSegSizeAllowed
  {
    UINT8 Length
    {
      Length == 4
    };
    UINT16 MaxSegSize;
  } MAX_SEG_SIZE_PAYLOAD;

The other cases are relatively straightforward, where
``SELECTIVE_ACK_PAYLOAD`` and ``TIMESTAMP_PAYLOAD`` illustrate the use
of variable length arrays.

.. code-block::c

  typedef struct _WINDOW_SCALE_PAYLOAD
  {
    UINT8 Length
    {
      Length == 3
    };
    UINT8 WindowScale;
  } WINDOW_SCALE_PAYLOAD;


  typedef struct _SELECTIVE_ACK_PAYLOAD
  {
    UINT8 Length
    {
      Length == 10 ||
      Length == 18 ||
      Length == 26 ||
      Length == 34
    };
    UINT8 SelectiveAck[:byte-size (Length - 2)];
  } SELECTIVE_ACK_PAYLOAD;

  
  typedef struct _TIMESTAMP_PAYLOAD
  {
    UINT8 Length
    {
      Length == 10
    };
    UINT8 TimeStamp[:byte-size (Length - 2)];
  } TIMESTAMP_PAYLOAD;

Finally, we can assemble our top-level TCP header type, as shown
below. The specification of the options array is weaker than it could
be. It currently permits an end-of-options-list option to appear
anywhere in the Options list, rather than as just the last
element. This can be improved by using a more advanced combinator from
EverParse, however we leave it as is for simplicity of this example.

.. code-block:: c

  /*++
    The top-level type of a TCP Header

    Arguments:

    * UINT32 SegmentLength, the size of the segment,
      including both header and data, passed in by the caller

    --*/
  entrypoint
  typedef struct _TCP_HEADER(UINT32 SegmentLength)
  {
    PORT            SourcePort;
    PORT            DestinationPort;
    SEQ_NUMBER      SeqNumber;
    ACK_NUMBER      AckNumber;
    UINT16          DataOffset:4
    { //DataOffset is in units of 32 bit words
      sizeof(this) <= DataOffset * 4 && //DataOffset points after the static fields
      DataOffset * 4 <= SegmentLength //and within the current segment
    };
    UINT16          Reserved:3
    {
      Reserved == 0 //Reserved bytes are unused
    };
    UINT16          NS:1;
    UINT16          CWR:1;
    UINT16          ECE:1;
    UINT16          URG:1;
    UINT16          ACK:1
    {
      AckNumber == 0 ||
      ACK == 1 //AckNumber can only be set if the ACK flag is set
    } ;
    UINT16          PSH:1;
    UINT16          RST:1;
    UINT16          SYN:1;
    UINT16          FIN:1;
    WINDOW          Window;
    CHECK_SUM       CheckSum;
    URGENT_PTR      UrgentPointer
    {
      UrgentPointer == 0 ||
      URG == 1 //UrgentPointer can only be set if the URG flag is set
    };
    //The SYN=1 condition indicates when MAX_SEG_SIZE option can be received
    //This is an array of options consuming
    OPTION(SYN==1)  Options[:byte-size (DataOffset * 4) - sizeof(this)];
    UINT8           Data[SegmentLength - (DataOffset * 4)];
  } TCP_HEADER;

  
The type is parameterized by ``SegmentLength``, the size in bytes
determined by the caller of the entire segment, including the header
and the data.

The first four fields, ``SourcePort``, ``DestinationPort``,
``SeqNumber`` and ``AckNumber`` are straightforward.

The ``DataOffset`` field is 4-bit value constrained to point beyond
the static fields of the header. Here ``sizeof(this)`` is a 3d
compile-time constant referring to the size of the non-variable length
prefix of the current type, i.e., the sum of the length in bytes of
all the fields up to the ``Options`` field. In this case, that number
is ``20``. ``DataOffset`` is also constrained to reference an offset
within the curent segment.

Next, we have 3 reserved bits, following by 1 bit each for the 9
flags. The ``Ack`` flag is interesting, since its constraints states
that the ``AckNumber`` can be non-zero only if the ``Ack`` bit is set.

Then, we have a ``Window`` and ``CheckSum``, both of which are
straightforward. Note, we do not specify the ``CheckSum`` as part of
the format---that's up to an application-specific check to
confirm. Alternatively, one could check this using a user-provided
action callback, though this is not yet supported.

The ``UrgentPointer`` field is similar to ``AckNumber`` in that it can
only be non-zero when the ``URG`` flag is set.

Then, we have an ``Options`` array, using the condition ``SYN==1`` to
determine the ``MaxSegSizeAllowed`` condition. The size in bytes of
the options array is variable and includes also the padding field, to
ensure 32-bit alignment. Note, this type is little too permissive, as
it will permit options arrays where the end-of-list option kind is not
necessarily only the last element.

Finally, we have the data field itself, whose byte size is bytes is
the computed expression.

Generated code
..............

Running the EverParse toolchain on the TCP segment header
specification produces a C procedure with the following signature, in ``TCPWrapper.h``:


.. code-block:: c

   BOOLEAN TcpCheckTcpHeader(uint32_t ___SegmentLength, uint8_t *base, uint32_t len);

This procedure is a validator for the ``TCP_HEADER`` type. The caller
passes in three parameters:

* ``__SegmentLength``, representing the ``SegmentLength`` argument of
  the ``TCPHeader`` type in the 3d specification.

* ``base``: a pointer to an array of bytes

* ``len``: a lower bound on the length of that array that ``base``
  points to.

``TcpCheckTcpHeader`` returns ``TRUE`` if, and only if, the contents
of ``base`` represent a valid ``TCPHeader``, while enjoying all the
guarantees of memory safety, arithmetic safety, double-fetch freedom,
not modifying any of the caller's memory, not allocating any heap
data, and being provably functional correct.

Error handling
..............

``TCPWrapper.h`` includes a default error handler to report the leaf
validation failure. It also expects a client module to supply an
implementation of

.. code-block:: c

   void TcpEverParseError(
        const char *TypeName,
        const char *FieldName,
        const char *Reason,
        uint64_t ErrorCode)
                

This can be instantiated with a procedure to, say, log an error.

Alternatively, the default error handler in ``TCPWrapper.h`` can be
replaced by a custom error handler of your choosing.


Fully worked examples: ELF files
---------------------------------

ELF (Executable and Linkable Format) is a common, standard file format
for various kinds of binary files (object files, executables, shared
libraries, and core dumps). The file format is described as
C-structures in the `elf.h
<https://man7.org/linux/man-pages/man5/elf.5.html>`_ file.

In this section we develop (parts of) a 3d specification for 64-bits
ELF files and describe how it can be integrated in existing projects
for validating potentially untrusted ELF files. A complete ELF
specification can be found in the `3d test suite
<https://github.com/project-everest/everparse/blob/master/src/3d/tests/ELF.3d>`_.

An ELF file consists of an ELF header, followed by a program header
table and a section header table. Both the tables are optional and
describe the rest of the ELF file. The ELF header specifies the
offsets and the number of entries in each of the tables. One
interesting aspect of validating ELF files is then to check that both
the tables contain the specified number of entries and point to the
valid parts of the rest of the ELF file.

The ELF header starts with a 16 byte array. The first four bytes of
the array are fixed: 0x7f, followed by 'E', 'L', and 'F'. Other bytes
of the array specify the binary architecture (32-bits or 64-bits),
endianness, ELF specification version, target OS, and ABI version of
the file. The last 7 bytes of the array are padding bytes set to 0. To
be able to constrain the individual bytes of this array, we specify in
3d as a struct.

.. code-block:: c

  typedef struct _E_IDENT
  {
    UCHAR    ZERO    { ZERO == 0x7f };
    UCHAR    ONE     { ONE == 0x45 };
    UCHAR    TWO     { TWO == 0x4c };
    UCHAR    THREE   { THREE == 0x46 };
  
    //This 3d spec applies to 64-bit only currently
    ELFCLASS FOUR    { FOUR == ELFCLASS64 };
    
    ELFDATA  FIVE;
  
    //ELF specification version is always set to 1
    UCHAR    SIX     { SIX == 1 };
  
    ELFOSABI SEVEN;
  
    //ABI version, always set to 0
    ZeroByte EIGHT;
  
    //padding, remaining 7 bytes are 0
    ZeroByte NINE_FIFTEEN[E_IDENT_PADDING_SIZE];
  } E_IDENT;

(The omitted definitions can be found in the `full development
<https://github.com/project-everest/everparse/blob/master/src/3d/tests/ELF.3d>`_.)


Following this 16 byte array, the ELF header specifies the file type,
file version, followed by fields of our interest: ``E_PHOFF``,
``E_SHOFF`` (offsets of the two tables), and ``E_PHNUM``, ``E_SHNUM``
(number of entries in the two tables).

.. code-block:: c

  // ELF HEADER BEGIN

  E_IDENT          IDENT;
  ELF_TYPE         E_TYPE       { E_TYPE != ET_NONE };

  UINT16           E_MACHINE;
  UINT32           E_VERSION    { E_VERSION == 1 };
  ADDRESS          E_ENTRY;

  //Program header table offset
  OFFSET           E_PHOFF;

  //Section header table offset
  OFFSET           E_SHOFF;
  
  UINT32           E_FLAGS;

  UINT16           E_EHSIZE     { E_EHSIZE == sizeof (this) };

  UINT16           E_PHENTSIZE;

  //Number of program header table entries
  UINT16           E_PHNUM
    { (E_PHNUM == 0 && E_PHOFF == 0) ||  //no Program Header table
      (0 < E_PHNUM && E_PHNUM < PN_XNUM &&
       sizeof (this) == E_PHOFF &&  //Program Header table starts immediately after the ELF Header
       E_PHENTSIZE == sizeof (PROGRAM_HEADER_TABLE_ENTRY)) };
  
  UINT16           E_SHENTSIZE;

  //Number of section header table entries
  UINT16           E_SHNUM
    { (E_SHNUM == 0 && E_SHOFF == 0) ||  // no Section Header table
      (0 < E_SHNUM && E_SHNUM < SHN_LORESERVE &&
       E_SHENTSIZE == sizeof (SECTION_HEADER_TABLE_ENTRY)) };

  //Section header table index of the section names table
  UINT16           E_SHSTRNDX
    { (E_SHNUM == 0 && E_SHSTRNDX == SHN_UNDEF) ||
      (0 < E_SHNUM  && E_SHSTRNDX < E_SHNUM) };
	
  // ELF HEADER END


The constraint on ``E_PHNUM`` enforces that either the file has no
program header table (``E_PHNUM == 0 && E_PHOFF == 0``) or the table
has non-zero number of entries and it starts immediately after the ELF
header (``sizeof (this)`` for the encapsulating struct type refers to
the ELF header shown here). We add similar constraints to ``E_SHNUM``
but do not add any check for ``E_SHOFF``, since unlike the
program header table, the section header table does not have a fixed
offset.

The ELF header is followed by the two optional tables. We specify
these optional tables using ``casetype``. First, the program header
table:

.. code-block:: c

  casetype _PROGRAM_HEADER_TABLE_OPT (UINT16 PhNum,
    				      OFFSET ElfFileSize)
  {
    switch (PhNum)
    {
      case 0:
        unit    Empty;
      default:
        PROGRAM_HEADER_TABLE_ENTRY(ElfFileSize)    Tbl[:byte-size sizeof (PROGRAM_HEADER_TABLE_ENTRY) * PhNum]
     }
  } PROGRAM_HEADER_TABLE_OPT;


The type ``PROGRAM_HEADER_TABLE_OPT`` is parameterized by
the number of program header table entries, as specified in the ELF
header, and the size of the ELF file; the latter allows us to check
that the segments pointed to by the program header table entries are in 
the file range.

In case ``PhNum`` is 0, the type is the empty ``unit``
type. Otherwise, it is an ``PROGRAM_HEADER_TABLE_ENTRY`` array of
size ``sizeof (PROGRAM_HEADER_TABLE_ENTRY) * PhNum`` bytes where the type
``PROGRAM_HEADER_TABLE_ENTRY`` describes a segment:


.. code-block:: c

  typedef struct _PROGRAM_HEADER_TABLE_ENTRY (OFFSET ElfFileSize)
  {
    UINT32    P_TYPE;

    UINT32    P_FLAGS  { P_FLAGS <= 7 };

    OFFSET    P_OFFSET;

    ADDRESS   P_VADDR;

    ADDRESS   P_PADDR;

    //The constraint checks that the segment is in the file range
    UINT64    P_FILESZ  { P_FILESZ < ElfFileSize &&
                          P_OFFSET <= ElfFileSize - P_FILESZ };
    UINT64    P_MEMSZ;

    UINT64    P_ALIGN;
  } PROGRAM_HEADER_TABLE_ENTRY;


The specification of the section header table is also a ``casetype``:

.. code-block:: c

  casetype _SECTION_HEADER_TABLE_OPT (OFFSET PhTableEnd,
                                      OFFSET ShOff,
                                      UINT16 ShNum,
  				      OFFSET ElfFileSize)
  {
    switch (ShNum)
    {
      case 0:
        NO_SECTION_HEADER_TABLE(PhTableEnd, ElfFileSize)                   NoTbl;      

      default:
        SECTION_HEADER_TABLE(PhTableEnd, ShOff, ShNum, ElfFileSize)        Tbl;
    }
  } SECTION_HEADER_TABLE_OPT;


We parameterize this type by the
offset where the program header table ends, the section header table
offset, number of section header table entries, and the size of the
file.

When number of entries is 0, the file does not have a section header
table, but we still need to check that the file contains enough bytes
after the program header table so that its total size is
``ElfFileSize``. ``NO_SECTION_HEADER_TABLE`` specifies such a type:

.. code-block:: c

  typedef struct _NO_SECTION_HEADER_TABLE (OFFSET PhTableEnd,
  					   UINT64 ElfFileSize)
  where (PhTableEnd <= ElfFileSize && ElfFileSize - PhTableEnd <= MAX_UINT32)
  {
    UINT8        Rest[:byte-size (UINT32) (ElfFileSize - PhTableEnd)];
  } NO_SECTION_HEADER_TABLE;


The checks in the ``where`` clause ensure safety of the arithmetic
operations.

In case the section header table is non-empty, we specify (a) the
bytes between the end of the program header table and the beginning of
the section header table, (b) the section header table, and (c) final
check that end of the section header table is the end of the file.

.. code-block:: c

  typedef struct _SECTION_HEADER_TABLE (OFFSET PhTableEnd,
                                        UINT64 ShOff,
                                        UINT16 ShNum,
				        OFFSET ElfFileSize)
  where (PhTableEnd <= ShOff && ShOff - PhTableEnd <= MAX_UINT32)
  {
    UINT8        PHTABLE_SHTABLE_GAP[(UINT32) (ShOff - PhTableEnd)];

    SECTION_HEADER_TABLE_ENTRY(ShNum, ElfFileSize)    SHTABLE[:byte-size sizeof (SECTION_HEADER_TABLE_ENTRY) * ShNum];

    // Check that we have consumed all the bytes in the file
    unit        EndOfFile
    {:on-success var x = field_pos; return (x == ElfFileSize); };  
  } SECTION_HEADER_TABLE;


The section header table, similar to the program header table, is an
array of entries.
  
Finally, the top-level ELF format:

.. code-block:: c


  entrypoint
  typedef struct _ELF (UINT64 ElfFileSize)
  {
    ... //ELF header as above

    //Optional Program Header table
    PROGRAM_HEADER_TABLE_OPT (E_PHNUM,
			      ElfFileSize)            PH_TABLE;

    //Optional Section Header Table
    //Recall that the first argument is the end of the program header table
    SECTION_HEADER_TABLE_OPT ((E_PHNUM == 0) ? E_EHSIZE : E_PHOFF + (sizeof (PROGRAM_HEADER_TABLE_ENTRY) * E_PHNUM),
                              E_SHOFF,
                              E_SHNUM,
			      ElfFileSize)            SH_TABLE;
  } ELF;


Integrating ELF validator in existing code
...........................................

To compile the 3d specification to C code, download the latest
`EverParse release
<https://github.com/project-everest/everparse/releases>`_ and compile
the 3d spec with the EverParse binary, e.g. for Windows:
``everparse.cmd --batch ELF.3d``. This command generates
``ELFWrapper.h`` and ``ELFWrapper.c`` files, with the top-level
validation function as follows:

.. code-block:: c

  BOOLEAN ElfCheckElf(uint64_t ___ElfFileSize, uint8_t *base, uint32_t len);

The actual validator implementation is generated in ``ELF.c``. To
integrate these validators into existing C code, drop in these
generated ``.c`` and ``.h`` files
in the development and invoke ```ElfCheckElf`` as necessary.


