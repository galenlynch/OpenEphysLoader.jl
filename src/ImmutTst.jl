#=module ImmutTst
type biz
  foo::bar
end
immutable bar
  patrons::Integer
end
end
=#
module Tst
type biz
  foo::bar
end
type bar
  patrons:Integer
end
end
using NormalTst
#using ImmutTst
