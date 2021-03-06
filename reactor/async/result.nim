# included from reactor/async.nim
import typetraits

type
  Result*[T] = object
    ## Either a value or an error.
    case isSuccess*: bool:
    of true:
      value*: T
    of false:
      error*: ref Exception

  InstantationInfo* = tuple[filename: string, line: int, procname: string]

  ExceptionMeta = ref object of Exception
    instInfo: InstantationInfo
    next: ExceptionMeta
    original: ref Exception

proc getOriginal*(exc: ref Exception): ref Exception =
  if exc of ExceptionMeta:
    return exc.ExceptionMeta.original.getOriginal
  else:
    return exc

when debugFutures:
  template extInstantiationInfo(depth: int= -1): untyped =
    let frame = getFrame()
    let info = instantiationInfo(depth - 1)
    (info.filename, info.line, $frame.procname).InstantationInfo

  proc getMeta(exc: ref Exception): ExceptionMeta =
    if exc of ExceptionMeta:
      return exc.ExceptionMeta
    else:
      return nil

  proc attachInstInfo(exc: ref Exception, info: InstantationInfo): ref Exception =
    let meta = ExceptionMeta(instInfo: info, next: getMeta(exc), msg: "[exception proxy]")
    meta.original = exc.getOriginal
    return meta
else:
  proc attachInstInfo(exc: ref Exception, info: InstantationInfo): ref Exception =
    return exc

  proc getMeta(exc: ref Exception): ExceptionMeta = nil

  proc extInstantiationInfo(depth: int= -1): InstantationInfo =
    ("", 0, "")

proc attachInstInfo(exc: string, info: InstantationInfo): ref Exception =
  assert exc != nil
  attachInstInfo(newException(Exception, exc), info)

proc formatAsyncTrace(meta: ExceptionMeta): string =
  if meta == nil:
    return ""
  let info = meta.instInfo
  let fn = "$1($2)" % [info.filename.split("/")[^1], $info.line]
  let line = fn & repeat(' ', max(24 - fn.len, 0)) & " " & (info.procname)
  line & "\n" & formatAsyncTrace(meta.next)

proc printError*(err: ref Exception) =
  let org = err.getOriginal()
  stderr.writeLine err.getStackTrace
  if err.getMeta() != nil:
    stderr.writeLine "Asynchronous trace:"
    stderr.writeLine formatAsyncTrace(err.getMeta())
  if org == nil:
    stderr.writeLine "Error: unknown (original exception: " & (if err == nil: "nil" else: err.repr) & ")"
  else:
    stderr.writeLine "Error: " & (if org.msg == nil: "nil" else: $org.msg) & " [" & (if org.name != nil: $org.name else: "Exception") & "]"

proc isError*[T](r: Result[T]): bool =
  return not r.isSuccess

proc just*[T](r: T): Result[T] =
  when T is void:
    Result[T](isSuccess: true)
  else:
    Result[T](isSuccess: true, value: r)

proc just*(): Result[void] =
  Result[void](isSuccess: true)

proc fillExceptionName*[Exc: ref Exception](exc: Exc) =
  when not (Exc is ref Exception):
    exc.name = name(type(exc))

proc error*[T; Exc: ref Exception](typename: typedesc[T], theError: Exc): Result[T] =
  assert theError != nil
  fillExceptionName(theError)
  Result[T](isSuccess: false, error: theError)

proc error*[T](typename: typedesc[T], theError: string): Result[T] =
  assert theError != nil
  Result[T](isSuccess: false, error: newException(Exception, theError))

proc get*[T](r: Result[T]): T =
  if r.isSuccess:
    when T is not void:
      return r.value
  else:
    raise r.error

proc `$`*[T](r: Result[T]): string =
  if r.isSuccess:
    when compiles($r.value):
      return "just(" & $(r.value) & ")"
    else:
      return "just(...)"
  else:
    let err = r.error.getOriginal
    return "error(" & (if err == nil or err.msg == nil: "nil" else: err.msg) & ")"

proc onSuccessOrErrorR*[T](f: Result[T], onSuccess: (proc(t:T)), onError: (proc(t:ref Exception))) =
  if f.isSuccess:
    when T is void:
      onSuccess()
    else:
      onSuccess(f.value)
  else:
    onError(f.error)

proc onSuccessOrErrorR*(f: Result[void], onSuccess: (proc()), onError: (proc(t:ref Exception))) =
  if f.isSuccess:
    onSuccess()
  else:
    onError(f.error)

template catchError*(e: untyped): untyped =
  ## Converts errors from `e` into error(...) and other results into just(e)
  try:
    when type(e) is Result:
      e
    else:
      just(e)
  except:
    when type(e) is Result:
      error(type(e.get), getCurrentException())
    else:
      error(type(e), getCurrentException())

# Future compat

proc getResult*(r: Result): auto = r

proc isCompleted*(r: Result): bool = true
