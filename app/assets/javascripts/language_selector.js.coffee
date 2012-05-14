$ ->
  $('#collection_country_ids').change ->
    ids = []
    $('select.country option:selected').each ->
      ids.push $(this).attr('value')

    $('select.language').each ->
      $(this).find('option').each ->
        $(this).attr('disabled', 'disabled')
        country_ids = $(this).data('country_id').split(',')
        for id in ids
          if id in country_ids
            $(this).removeAttr('disabled').insertBefore($(this).children().first())
            break
      # Tell chosen we changed the list
      $(this).trigger('liszt:updated')
