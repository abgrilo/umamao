$(document).ready(function () {

  // As the :empty pseudo-class isn't dynamic, we cannot
  // use it in our CSS. Instead, we use a regular "empty" class and
  // manage it in Javascript.

  // Unselect all contacts link
  $("#select-contacts a.remove_all").click(function () {
    $("#contacts-to-invite").addClass("empty");
    $("#contacts-to-invite .list").empty();
  });

  $("#contacts-to-invite .contact .remove").live("click", function () {
    $(this).closest(".contact").remove();
    if ($("#contacts-to-invite .list").is(":empty")) {
      $("#contacts-to-invite").addClass("empty");
    }
  });

  $("#import-contacts a").click(function () {
    var url = $(this).attr("href");
    var template =  $("#import-contacts .template").clone();
    template.find("a.continue").attr("href", url);
    Utils.modal({html: template.html()});
    return false;
  });

  var controls = $("#select-contacts .controls");

  if (controls.is(".waiting")) {
    // Need to wait for server to fetch external contacts

    var waitNotice = $("#select-contacts .wait-notice");

    var signalError = function () {
      Utils.showMessage(waitNotice.attr("data-error-message"), "error");
    };

    $.ajax({
      dataType: "json",
      error: signalError,
      success: function (data) {
        waitNotice.slideUp("slow", function () {
          waitNotice.remove();
          controls.removeClass("waiting");
          if (!data.success) {
            signalError();
          }
        });
      },
      type: "POST",
      url: waitNotice.attr("data-fetch-contacts-url")
    });
  }

  var invitedContactTemplate = $.template(null,
    '<div class="contact">' + Utils.closeLink() +
    '<input type="hidden" name="emails[]" value="${email}" />' +
    '<div class="name">${name}</div>' +
    '<div class="email">${email}</div></div>');

  var addContactToList = function (contact) {
    $("#contacts-to-invite").removeClass("empty");
    $("#contacts-to-invite .list").
      prepend($.tmpl(invitedContactTemplate, contact));
  };

  var contactAutocomplete = new AutocompleteBox("#search-contacts",
                                                "#search-contacts-results");

  var addInputToList = function () {
    addContactToList({name: "", email: contactAutocomplete.input.val()});
    contactAutocomplete.clear();
  };

  controls.find(".add-contact").click(function () {
    if (contactAutocomplete.isActive &&
        contactAutocomplete.input.val().trim())
      addInputToList();
    return false;
  });

  var autocompleteTemplate = $.template(null,
    '<li class="autocomplete-entry">${name} ' +
    '<span class="desc">${email}</span></li>');


  var ContactItem = function (contact) {
    this.data = contact;
    this.html = $.tmpl(autocompleteTemplate, contact);
  };

  ContactItem.prototype = {
    click: function () {
      addContactToList(this.data);
      contactAutocomplete.clear();
    }
  };

  Utils.extend(ContactItem, Item);

  contactAutocomplete.processData = function (data) {
    var items = [];

    data.forEach(function (result) {
      items.push(new ContactItem(result));
    });

    return items;
  };

  contactAutocomplete.returnDefault = addInputToList;

  $("#select-contacts-form").submit(function () {
    if (!contactAutocomplete.input.is(".inactive")) {
      var typedEmail = $('<input name="emails[]" type="hidden" />').
        attr("value", contactAutocomplete.input.val());
      $("#select-contacts-form").append(typedEmail);
    }
  });

});