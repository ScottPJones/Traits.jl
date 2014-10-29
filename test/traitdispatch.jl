function compare_code_native(f1, f2, types)
    # A very crude way to compare whether two functions produce the
    # same machine code: compare their lengths.  Returns the relative
    # difference of the length of code_native of two functions.
    #
    # Note, when running with --code-coverage the traits-functions
    # will be much longer than the duck-typed ones.
    df1 = Base._dump_function(f1, types, true, false)
    df2 = Base._dump_function(f2, types, true, false)
    # the first two lines have some file names, etc
    df1 = *(split(df1, "\n")[3:end]...)
    df2 = *(split(df2, "\n")[3:end]...)
    abs(length(df1)-length(df2))/length(df2)
end

###############
# recreate manual-traitdispatch.jl: f2

@traitfn ttf2{X,Y<:Integer; D1{Y}, D4{X,Y}}(x::X,y::Y) = x + sin(y)
@traitfn ttf2{S,T<:Integer; D1{S}, D1{T}  }(s::S,t::T) = sin(s) - sin(t)
@traitfn ttf2{X,Y<:FloatingPoint; D1{X}, D1{Y}  }(x::X,y::Y) = cos(x) - cos(y)

@test_throws Traits.TraitException ttf2(4,5) # ambiguous trait-type
@test ttf2(4,5.) == cos(4)-cos(5.)

@test ttf2(MTT1(5),4) == sin(5)-sin(4)
@test ttf2(MTT2(5),3) == sin(3)+5

@test length(methods(f2))==length(methods(ttf2))

################
@traitfn ft1{X,Y; Eq{X,Y}}(x::X,y::Y) = x==y
ff1(x,y) = x==y
@test ff1(4,5)==ft1(4,5)
# @code_llvm ft1(4,5)
# @code_llvm ff1(4,5)
@test 0.02<compare_code_native(ff1, ft1, (Int,Int))<0.03
@test 0.015compare_code_native(ff1, ft1, (BigFloat,BigInt))<0.025

#################
@traitfn function ft2{X,Y; Arith{X,Y}}(x::X,y::Y) 
    out = zero(promote(x,y)[1])
    for xe in 1:iround(x)
        out += xe + y
    end
    out
end
function ff2{X,Y}(x::X,y::Y) 
    out = zero(promote(x,y)[1])
    for xe in 1:iround(x)
        out += xe + y
    end
    out
end
        
@test ff2(7.3,5.)==ft2(7.3,5.)
# check the generated code is within some % of each other
@test 0.06<compare_code_native(ff2, ft2, (Int,Int))<0.07
@test 0.09<compare_code_native(ff2, ft2, (BigFloat,BigInt))<0.1
# @code_llvm ft2(7.3,5.)
# @code_llvm ff2(7.3,5.)



##################

@traitfn ft3{X1,X2; Iter{X1}}(x::X1,y::X2) = (out=X2[]; for i in x; push!(out,i+y) end; out)
ff3{Y}(x,y::Y) = Y[i+y for i in x]

@test ff3([1:10],5)==ft3([1:10],5)
@test ff3(BigFloat[1:10],BigInt(5))==ft3(BigFloat[1:10],BigInt(5))
# @code_llvm ft3([1:10],5)
# @show "---------------------------------------------------"
# @code_llvm ff3([1:10],5)
@test compare_code_native(ff3, ft3, (Array{Int,1},Int))<0.17
@test compare_code_native(ff3, ft3, (Array{BigFloat,1},BigInt))<0.1


###############
@traitdef MyTr{X,Y} begin
    foobar(X,Y) -> Bool
end
type A
    a::Int
end
foobar(a::A, b::A) = a.a==b.a
@test istrait(MyTr{A,A})  # true
@test istrait(MyTr{Int,Int})==false

# make a function which dispatches on traits:
@traitfn ft111{X,Y; Cmp{X,Y}}(x::X,y::Y)  = x>y ? 5 : 6
@traitfn ft111{X,Y; MyTr{X,Y}}(x::X,y::Y) = foobar(x,y) ? -99 : -999

@test ft111(4,5)==6
@test ft111(A(5), A(6))==-999

@test_throws TraitException ft111("asdf", 5)
foobar(a::String, b::Int) = length(a)==b
@test ft111("asdf", 4)==-99

## dispatch using subtraits
@traitdef MyTr2{X,Y} <: MyTr{X,Y} begin
    bar(X,Y) -> Bool
end

@traitfn gt1{X,Y; MyTr2{X,Y}}(x::X,y::Y)  = "MyTr2"
@traitfn gt1{X,Y; MyTr{X,Y}}(x::X,y::Y)   = "MyTr"

type B1
    a::Int
end
foobar(a::B1, b::B1) = a.a==b.a
type B2
    a::Int
end
foobar(a::B2, b::B2) = a.a==b.a
bar(a::B2, b::B2) = a.a==b.a
@test istrait(MyTr{B1,B1})  # true
@test istrait(MyTr2{B1,B1})==false
@test istrait(MyTr2{B2,B2})

@test gt1(B1(1), B1(1))=="MyTr"
@test gt1(B2(1), B2(1))=="MyTr2" 


##########
## adding trait methods to existing functions:
@traitdef MyTr7{X} begin
    bobo(X) -> String
end

abstract AMTyp7
type MTyp71 <: AMTyp7
end
type MTyp72 <: AMTyp7
end
# add to above trait
@traitimpl MyTr7{MTyp71} begin
    bobo(X::MTyp71) = "Yeah"
end

import Base.sin
@traitfn sin{X; MyTr7{X}}(x::X) = bobo(x)
@test sin(MTyp71())=="Yeah"
@test_throws TraitException sin(MTyp72())
@test length(traitmethods(sin))==1

@traitfn Base.cos{X; MyTr7{X}}(x::X) = bobo(x)
@test cos(MTyp71())=="Yeah"
@test_throws TraitException cos(MTyp72())
