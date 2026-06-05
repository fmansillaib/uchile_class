clear all 

import excel "/Volumes/GoogleDrive-111868847232940162537/Mi unidad/SOFTWARE-SHOP/Webcast/2022/Arboles de Decisión y Ensamble Learning/BD.Modelo de Crédito.xlsx", sheet("Base de Datos") firstrow
rename *, lower 

tab default

*Generamos muestra de Entrenamiento y Prueba.
splitsample, generate(muestra, replace) split(0.8 0.2) show rseed(123456789)

tab muestra
tab default if muestra == 1 
tab default if muestra == 2  

*--------------*
*MODELO CLASICO*
*--------------*
logit default ratio_deuda_ingreso year_permanencia deuda_tc year_permanencia_area if muestra == 1
predict clas_logit, pr
replace clas_logit = 1 if clas_logit >=0.3
replace clas_logit = 0 if clas_logit !=1
roctab clas_logit default if muestra == 1, graph summary name(logit_1, replace)
roctab clas_logit default if muestra == 2, graph summary name(logit_2, replace)
graph combine logit_1 logit_2

*-----------------------*
*MODELO MACHINE LEARNING*
*-----------------------*

*Definir las variables explicativas en Nivel
ds default muestra clas_logit , not varwidth(32)
global var_x_nivel = r(varlist)

*Forma de diferenciar las variables entre los grupos, mediante t-student y fisher.
matrix A = J(8, 5, .)
matrix rowname A = $var_x_nivel
matrix colname A = Media_Grupo1 Media_Grupo2 t-Student pval_t pval_fisher

local f = 1
foreach i in $var_x_nivel {
display "`i'"

sdtest `i' if muestra == 1, by(default)
matrix A[`f',5] = round(r(p), 0.00001)*100

if r(p) <= 0.01 {
ttest `i' if muestra == 1, by(default) unequal
matrix A[`f',1] = r(mu_1)
matrix A[`f',2] = r(mu_2)
matrix A[`f',3] = r(t)
matrix A[`f',4] = round(r(p), 0.00001)*100
}

else {
ttest `i' if muestra == 1, by(default) 
matrix A[`f',1] = r(mu_1)
matrix A[`f',2] = r(mu_2)
matrix A[`f',3] = r(t)
matrix A[`f',4] = round(r(p), 0.00001)*100
}

local ++f
}
matrix list A

*Estadarizacion de Variables
ds default muestra, not varwidth(32)
global var_cont = r(varlist)

foreach i in $var_cont {
sum `i'
gen est_`i' = (`i' - r(mean))/r(sd)
}

*Establecer de Variables Estandarizadas
ds est_* , varwidth(32)
global var_x_est = r(varlist)

*Creacion del Modelo.
*Autor: Rosie Yuyan Zou & Matthias Schonlau, Waterloo
help rforest 

*Modelo 1: Variables estandarizadas
rforest default $var_x_est if muestra==1, type(class) iterations(30) depth(30)

predict c1 c2 , pr 
gen c2_r = 1 if c2 >=0.3
replace c2_r = 0 if c2 <0.3

roctab c2_r default if muestra == 1, graph summary name(rf_est_1, replace)
roctab c2_r default if muestra == 2, graph summary name(rf_est_2, replace)
graph combine rf_est_1 rf_est_2, name(graph_combine_est)
*ROC AREA ENTRENAMIENTO: 0.9593
*ROC AREA PRUEBA: 		 0.7378
drop c1 c2 c2_r 

*------------------------*
* HIPERPARAMETROS OPTIMOS*
*------------------------*



*----------------------*
* FORMA 1: FORMA FRAME *
*----------------------*
frame create resultados num_arbol num_ramas roc_entrenamiento roc_prueba

forvalues i = 2(1)10{ //Numero de Ramas
forvalues j = 5(1)20{ //Numero de Arboles

rforest default $var_x_nivel if muestra==1, type(class) iterations(`j') depth(`i') seed(123456)

predict c1 c2 , pr 
gen c2_r = 1 if c2 >= 0.3
replace c2_r = 0 if c2 < 0.3

roctab c2_r default if muestra == 1, summary
local roc_entrenamiento = r(ub)
roctab c2_r default if muestra == 2, summary
local roc_prueba = r(ub)

frame post resultados (`j') (`i') (`roc_entrenamiento') (`roc_prueba')

drop c1 c2 c2_r
}
}

*-----------------------------------*
*Grafico de Hiper Parametros Optimos*
*-----------------------------------*
frame change resultados
gen dif = roc_entrenamiento-roc_prueba
twoway (contour dif num_arbol num_ramas, levels(100) interp(shepard) crule(chue)), ymtick(##5) xlabel(#5) xmtick(##1) zlabel(-0.1(0.02)0.22) caption(dif = roc_entrenamiento - roc_prueba) name(graph_hp_opt, replace)
*------------*
*MODELO FINAL*
*------------*
frame change default
rforest default $var_x_nivel if muestra==1, type(class) iterations(11) depth(3)

predict c1 c2 , pr 
gen c2_r = 1 if c2>=0.3
replace c2_r = 0 if c2<0.3

roctab c2_r default if muestra == 1, graph summary name(rf_hp_opt_1, replace)
roctab c2_r default if muestra == 2, graph summary name(rf_hp_opt_2, replace)
graph combine rf_hp_opt_1 rf_hp_opt_2, name(graph_rf_hp_opt)
*ROC AREA ENTRENAMIENTO: 0.7669
*ROC AREA PRUEBA: 0.7527

table default clas_logit
table default c2_r

drop c1 c2 c2_r 

*----------------------------*
*IMPORTANCIA DE LAS VARIABLES*
*----------------------------*
rforest default $var_x_nivel if muestra==1, type(class) iterations(9) depth(3)

matrix importance = e(importance)
svmat importance
*drop importance 

gen id=""
local mynames : rownames importance
local k : word count `mynames'
// If there are more variables than observations
if `k'>_N {
set obs `k'
}
forvalues i = 1(1)`k' {
local aword : word `i' of `mynames'
local alabel : variable label `aword'
if ("`alabel'"!="") qui replace id= "`alabel'" in `i'
else qui replace id= "`aword'" in `i'
}

graph hbar (mean) importance, over(id, sort(1) label(labsize(vsmall))) ytitle(Importance) name(importance_variables)

