/* Copyright (C) 2018 Freetech Solutions

 This file is part of OMniLeads

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License version 3, as published by
 the Free Software Foundation.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with this program.  If not, see http://www.gnu.org/licenses/.

*/
$(function () {
    var $mostrarFormCalificacion = $('#mostrarFormCalificacion');
    var $opcion_calificar = $('#id_opcion_calificacion');
    $opcion_calificar.removeAttr('required');
    $mostrarFormCalificacion.on('click', function () {
        $('div[data="toHide"]').each( function () {
            var $formCalificacion = $(this);
            var checkedValue = $mostrarFormCalificacion.is(':checked');
            // se pasa el valor de la selección o no del formulario al input
            // por otra parte, de acuerdo a este valor, se muestra o no el formulario de calificación
            $mostrarFormCalificacion.val(checkedValue);
            if (checkedValue == false) {
                $formCalificacion.attr('class', 'hidden');
            }
            else {
                $formCalificacion.attr('class', '');
                $opcion_calificar.attr('required');
            }
        });
    });
    subscribeToChangeOptionCalification($opcion_calificar);
    // si la campaña permite calificaciones a telefonos
    // se sincronizan los select(s) asociados a las calificaciones de los campos seleccionados con
    // los respectivos campos en el formulario de contacto
    // console.log($('#permitirCalificacionTelefono'));
    // console.log($('.calificacionTelefonoValor'));
    $('.calificacionTelefonoValor').each(function(index) {
        var $currentNode = $(this);
        var $clon = $currentNode.clone().attr('id', 'clon' + index);
        $clon.val($currentNode.val());
        var campo = $clon.attr('data-id');
        $('#contacto-' + campo).append($clon);
        $clon.on('change', function() {
            var valueSelected = $(this).find("option:selected").val();
            $currentNode.val(valueSelected);
            $currentNode.find('option').prop('selected', false);
            $currentNode.find(`option[value="${valueSelected}"]`).prop('selected', true);
        });
    });
});

function subscribeToChangeOptionCalification(opcion_calificar) {
    $(opcion_calificar).change(function(){
        var $nombre_subcalificaciones = JSON.parse($('#id_nombre_subcalificaciones').val().replace(/'/g, '"'));
        $nombre_subcalificaciones.forEach((obj, index) => {
            if (obj['id'] == opcion_calificar.val()){
                $('#id_subcalificacion').empty();
                let option_0 = document.createElement('option');
                option_0.value = '';
                option_0.text = '---------';
                option_0.selected = true;
                $('#id_subcalificacion').append(option_0);
                obj['subcalificaciones'].forEach(opcion => {
                    let option = document.createElement('option');
                    option.value = opcion;
                    option.text = opcion;
                    $('#id_subcalificacion').append(option);
                });
            }
        });
    });
}
